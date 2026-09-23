import { execFile } from 'node:child_process'
import { readFile, unlink } from 'node:fs/promises'
import path from 'node:path'
import { promisify } from 'node:util'
import { UTCDate } from '@date-fns/utc'
import { addDays, format, startOfDay } from 'date-fns'
import { delay } from 'es-toolkit'
import ky from 'ky'
import { z } from 'zod'

const exec = promisify(execFile)
const http = ky.create({ retry: 0, throwHttpErrors: false, timeout: 30_000 })

const INGEST_PATH = '/api/usage/ingest'
const DEFAULT_INGEST_URL = 'https://cho.sh'
const DEFAULT_DAYS = 30
const DEFAULT_CHROME_PROFILES = 'anaclumos,wondermaxxing,Starcovery,twelvelabs.io'
const REQUIRED_CHROME_PROFILES = ['anaclumos', 'wondermaxxing', 'Starcovery', 'twelvelabs.io'] as const
const UNATTRIBUTED_MODEL = '(unattributed)'

const exportPy = path.join(import.meta.dir, 'cursor-usage-export.py')

export class SourceUnavailableError extends Error {
  override name = 'SourceUnavailableError'
}

const utcDayStart = (d: Date): Date => startOfDay(new UTCDate(d))
const isoDate = (d: Date): string => format(new UTCDate(d), 'yyyy-MM-dd')

interface TokenRow {
  cacheTokens: number
  date: string
  inputTokens: number
  model: string
  outputTokens: number
  provider: 'cursor'
  requestCount: number
}

interface CostRow {
  costUsd: number
  date: string
  model: string
  provider: 'cursor'
}

export interface CursorCsvRows {
  costRows: CostRow[]
  tokenRows: TokenRow[]
}

export interface IngestRow {
  costUsd?: number
  date: string
  inputTokens: number
  model: string
  outputTokens: number
  provider: 'cursor'
  requestCount: number
}

const REQUIRED_COLUMNS = [
  'Date',
  'Kind',
  'Model',
  'Input (w/ Cache Write)',
  'Input (w/o Cache Write)',
  'Cache Read',
  'Output Tokens',
  'Total Tokens',
  'Cost',
] as const

type RequiredColumn = (typeof REQUIRED_COLUMNS)[number]

const emptyRows = (): CursorCsvRows => ({ costRows: [], tokenRows: [] })

const splitCsvLine = (line: string): string[] => {
  const fields: string[] = []
  let current = ''
  let inQuotes = false
  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i]
    if (inQuotes) {
      if (ch === '"') {
        if (line[i + 1] === '"') {
          current += '"'
          i += 1
        } else {
          inQuotes = false
        }
      } else {
        current += ch
      }
      continue
    }
    if (ch === '"') {
      inQuotes = true
      continue
    }
    if (ch === ',') {
      fields.push(current)
      current = ''
      continue
    }
    current += ch
  }
  fields.push(current)
  return fields
}

const parseCount = (value: string): number => {
  if (value === '') {
    return 0
  }
  const n = Number(value)
  if (!Number.isFinite(n) || n < 0) {
    throw new Error(`cursor csv: non-numeric token field ${JSON.stringify(value)}`)
  }
  return n
}

const parseCostUsd = (value: string): number | undefined => {
  if (value === '' || value === 'Included' || value === 'Free' || value === '-') {
    return undefined
  }
  const withoutCommas = value.replaceAll(',', '').trim()
  const normalized = withoutCommas.startsWith('$') ? withoutCommas.slice(1).trim() : withoutCommas
  const n = Number(normalized)
  if (!Number.isFinite(n) || n < 0 || normalized === '') {
    throw new Error(`cursor csv: unrecognized Cost ${JSON.stringify(value)}`)
  }
  return n > 0 ? n : undefined
}

export const parseCursorUsageCsv = (csvText: string): CursorCsvRows => {
  const lines = csvText.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n').filter(Boolean)
  if (lines.length === 0) {
    return emptyRows()
  }
  const header = splitCsvLine(lines[0])
  const columnIndex = (col: RequiredColumn): number => {
    const i = header.indexOf(col)
    if (i === -1) {
      throw new Error(`cursor csv: missing column ${col}`)
    }
    return i
  }
  const index: Record<RequiredColumn, number> = {
    'Cache Read': columnIndex('Cache Read'),
    Cost: columnIndex('Cost'),
    Date: columnIndex('Date'),
    'Input (w/ Cache Write)': columnIndex('Input (w/ Cache Write)'),
    'Input (w/o Cache Write)': columnIndex('Input (w/o Cache Write)'),
    Kind: columnIndex('Kind'),
    Model: columnIndex('Model'),
    'Output Tokens': columnIndex('Output Tokens'),
    'Total Tokens': columnIndex('Total Tokens'),
  }
  const rows = emptyRows()
  for (const line of lines.slice(1)) {
    const fields = splitCsvLine(line)
    const cell = (col: RequiredColumn): string => fields[index[col]] ?? ''
    if (cell('Date').length === 0) {
      throw new Error('cursor csv: empty Date')
    }
    const cacheWrite = parseCount(cell('Input (w/ Cache Write)'))
    const input = parseCount(cell('Input (w/o Cache Write)'))
    const cacheRead = parseCount(cell('Cache Read'))
    const outputTokens = parseCount(cell('Output Tokens'))
    const inputTokens = input + cacheWrite + cacheRead
    const costUsd = parseCostUsd(cell('Cost'))
    if (inputTokens === 0 && outputTokens === 0 && costUsd === undefined) {
      continue
    }
    const date = isoDate(new UTCDate(cell('Date')))
    const model = cell('Model') || UNATTRIBUTED_MODEL
    if (inputTokens > 0 || outputTokens > 0) {
      rows.tokenRows.push({
        cacheTokens: 0,
        date,
        inputTokens,
        model,
        outputTokens,
        provider: 'cursor',
        requestCount: 1,
      })
    }
    if (costUsd !== undefined) {
      rows.costRows.push({
        costUsd,
        date,
        model,
        provider: 'cursor',
      })
    }
  }
  return rows
}

export const aggregateCursorCsvRows = (parsed: CursorCsvRows): IngestRow[] => {
  const byKey = new Map<
    string,
    {
      costUsd: number
      date: string
      hasCost: boolean
      inputTokens: number
      model: string
      outputTokens: number
      requestCount: number
    }
  >()
  for (const row of parsed.tokenRows) {
    const key = `${row.date}|${row.model}`
    const acc = byKey.get(key)
    if (!acc) {
      byKey.set(key, {
        costUsd: 0,
        date: row.date,
        hasCost: false,
        inputTokens: row.inputTokens,
        model: row.model,
        outputTokens: row.outputTokens,
        requestCount: row.requestCount,
      })
      continue
    }
    acc.inputTokens += row.inputTokens
    acc.outputTokens += row.outputTokens
    acc.requestCount += row.requestCount
  }
  for (const row of parsed.costRows) {
    const key = `${row.date}|${row.model}`
    const acc = byKey.get(key)
    if (!acc) {
      byKey.set(key, {
        costUsd: row.costUsd,
        date: row.date,
        hasCost: true,
        inputTokens: 0,
        model: row.model,
        outputTokens: 0,
        requestCount: 0,
      })
      continue
    }
    acc.costUsd += row.costUsd
    acc.hasCost = true
  }
  return [...byKey.values()].map(({ hasCost, costUsd, ...row }) =>
    hasCost ? { ...row, costUsd, provider: 'cursor' as const } : { ...row, provider: 'cursor' as const },
  )
}

export const requireAggregatedCursorCsv = (csvText: string, label: string): IngestRow[] => {
  if (csvText.trim() === '') {
    throw new SourceUnavailableError(`${label}: CSV is empty (download did not finish)`)
  }
  const rows = aggregateCursorCsvRows(parseCursorUsageCsv(csvText))
  if (rows.length === 0) {
    throw new SourceUnavailableError(`${label}: 0 aggregated (date, model) rows`)
  }
  return rows
}

export interface BrowserExportCleanup {
  cleanup: () => Promise<void>
}

export type CursorBrowserCleanupOutcome =
  | 'dry-run'
  | 'ingest-confirmed'
  | 'no-rows'
  | 'post-failed'
  | 'workflow-failed'

export const shouldCleanupBrowserExports = (outcome: CursorBrowserCleanupOutcome): boolean =>
  outcome === 'no-rows' || outcome === 'ingest-confirmed'

export const maybeCleanupBrowserExports = async (
  exports: BrowserExportCleanup[],
  outcome: CursorBrowserCleanupOutcome,
): Promise<void> => {
  if (!shouldCleanupBrowserExports(outcome)) {
    return
  }
  await Promise.all(exports.map((entry) => entry.cleanup()))
}

const mergeRows = (all: IngestRow[]): IngestRow[] => {
  const byKey = new Map<string, IngestRow & { hasCost: boolean }>()
  for (const row of all) {
    const key = `${row.date}|${row.model}`
    const acc = byKey.get(key)
    if (!acc) {
      byKey.set(key, { ...row, hasCost: row.costUsd !== undefined })
      continue
    }
    acc.inputTokens += row.inputTokens
    acc.outputTokens += row.outputTokens
    acc.requestCount += row.requestCount
    if (row.costUsd !== undefined) {
      acc.costUsd = (acc.costUsd ?? 0) + row.costUsd
      acc.hasCost = true
    }
  }
  return [...byKey.values()].map(({ hasCost, ...row }) => (hasCost ? row : { ...row, costUsd: undefined }))
}

const lastNonEmptyLine = (text: string): string => {
  const lines = text
    .split('\n')
    .map((line) => line.trim())
    .filter(Boolean)
  const last = lines.at(-1)
  if (!last) {
    throw new Error('cursor-usage-export printed no path')
  }
  return last
}

const deleteLocalPath = async (filePath: string): Promise<void> => {
  try {
    await unlink(filePath)
  } catch (error) {
    const code = z.object({ code: z.string() }).safeParse(error)
    if (code.success && code.data.code === 'ENOENT') {
      return
    }
    console.log(`warning: could not delete ${filePath}: ${String(error)}`)
  }
}

const collect = async <T>(
  label: string,
  skipped: string[],
  task: () => Promise<T>,
): Promise<T | null> => {
  try {
    return await task()
  } catch (error) {
    if (!(error instanceof SourceUnavailableError)) {
      throw error
    }
    skipped.push(label)
    console.error(`skipping ${label}`, error)
    return null
  }
}

interface ExecSourceOptions {
  env?: NodeJS.ProcessEnv
  maxBuffer?: number
  timeout?: number
}

const execSource = async (
  file: string,
  args: string[],
  options: ExecSourceOptions,
): Promise<{ stderr: string; stdout: string }> => {
  try {
    return await exec(file, args, options)
  } catch (error) {
    throw new SourceUnavailableError(String(error))
  }
}

interface BrowserExport {
  cleanup: () => Promise<void>
  rows: IngestRow[]
}

interface ChromeProfile {
  directory: string
  name: string
}

const listChromeProfiles = async (): Promise<ChromeProfile[]> => {
  const { stdout, stderr } = await execSource('python3', [exportPy, '--list-profiles'], {
    maxBuffer: 1024 * 1024,
    timeout: 15_000,
  })
  if (stderr) {
    console.log(stderr.trimEnd())
  }
  const profiles: ChromeProfile[] = []
  for (const line of stdout.split('\n')) {
    const trimmed = line.trim()
    if (!trimmed) {
      continue
    }
    const sep = trimmed.indexOf('\t')
    if (sep === -1) {
      profiles.push({ directory: trimmed, name: '' })
      continue
    }
    profiles.push({
      directory: trimmed.slice(0, sep),
      name: trimmed.slice(sep + 1),
    })
  }
  if (profiles.length === 0) {
    throw new SourceUnavailableError('Chrome Local State listed no user profiles')
  }
  return profiles
}

const parseRequiredList = (
  raw: string | undefined,
  fallback: string,
  required: readonly string[],
  envName: string,
): string[] => {
  const trimmed = (raw ?? '').trim()
  const values = [
    ...new Set(
      (trimmed.length === 0 ? fallback : trimmed)
        .split(',')
        .map((value) => value.trim())
        .filter(Boolean),
    ),
  ]
  for (const name of required) {
    if (!values.includes(name)) {
      throw new Error(
        `${envName} must include ${required.join(' and ')} (got ${values.join(',') || '(empty)'}); a partial list would REPLACE-wipe omitted accounts`,
      )
    }
  }
  return values
}

const resolveChromeProfiles = async (raw: string | undefined): Promise<string[]> => {
  const wanted = parseRequiredList(
    raw,
    DEFAULT_CHROME_PROFILES,
    REQUIRED_CHROME_PROFILES,
    'CURSOR_USAGE_CHROME_PROFILES',
  )
  const known = await listChromeProfiles()
  return wanted.map((want) => {
    const match = known.find((profile) => profile.directory === want || profile.name === want)
    if (!match) {
      throw new Error(
        `CURSOR_USAGE_CHROME_PROFILES names an unknown Chrome profile (${want}); known: ${known
          .map((profile) => profile.name || profile.directory)
          .join(', ')}`,
      )
    }
    return match.directory
  })
}

const exportOnProfile = async (profile: string, days: number): Promise<BrowserExport> => {
  const { stdout, stderr } = await execSource('python3', [exportPy], {
    env: {
      ...process.env,
      CURSOR_USAGE_CHROME_PROFILE: profile,
      CURSOR_USAGE_DAYS: String(days),
    },
    maxBuffer: 16 * 1024 * 1024,
    timeout: 120_000,
  })
  if (stderr) {
    console.log(stderr.trimEnd())
  }
  const csvPath = lastNonEmptyLine(stdout)
  let csvText: string
  try {
    csvText = await readFile(csvPath, 'utf-8')
  } catch (error) {
    throw new SourceUnavailableError(String(error))
  }
  const rows = requireAggregatedCursorCsv(csvText, `Chrome ${profile} ${csvPath}`)
  console.log(`Chrome ${profile} ${csvPath}: ${rows.length} aggregated (date, model) rows`)
  return {
    cleanup: async () => {
      await deleteLocalPath(csvPath)
    },
    rows,
  }
}

const exportAllProfiles = async (
  profiles: string[],
  days: number,
  skipped: string[],
): Promise<BrowserExport[]> => {
  const exports: BrowserExport[] = []
  for (const profile of profiles) {
    const entry = await collect(`Chrome ${profile}`, skipped, () => exportOnProfile(profile, days))
    if (entry) {
      exports.push(entry)
    }
  }
  return exports
}

const run = async () => {
  const ingestUrl = process.env.USAGE_INGEST_URL ?? DEFAULT_INGEST_URL
  const rawDays = process.env.CURSOR_USAGE_DAYS
  let days = DEFAULT_DAYS
  if (rawDays !== undefined && rawDays.trim() !== '') {
    const parsed = Number(rawDays)
    if (!Number.isFinite(parsed) || parsed <= 0 || !Number.isInteger(parsed)) {
      throw new Error(`CURSOR_USAGE_DAYS must be a positive integer (got ${JSON.stringify(rawDays)})`)
    }
    days = parsed
  }
  const dryRun = process.env.USAGE_DRY_RUN === '1'
  const cutoff = isoDate(addDays(utcDayStart(new UTCDate()), -(days - 1)))
  const skipped: string[] = []

  const profiles =
    (await collect('Chrome profiles', skipped, () =>
      resolveChromeProfiles(process.env.CURSOR_USAGE_CHROME_PROFILES),
    )) ?? []
  const browserExports = await exportAllProfiles(profiles, days, skipped)
  const skippedNote = skipped.length > 0 ? `; skipped ${skipped.join(', ')}` : ''

  const rows = mergeRows(browserExports.flatMap((entry) => entry.rows)).filter(
    (row) => row.date >= cutoff,
  )
  if (rows.length === 0) {
    await maybeCleanupBrowserExports(browserExports, 'no-rows')
    if (skipped.length > 0) {
      throw new Error(`no Cursor usage rows collected${skippedNote}`)
    }
    console.log('no Cursor usage rows from any source')
    return
  }
  const tokens = rows.reduce((sum, row) => sum + row.inputTokens + row.outputTokens, 0)

  if (dryRun) {
    console.log(
      `DRY RUN: ${rows.length} cursor merged (date, model) rows (Chrome ${profiles.join('+')}); ${tokens.toLocaleString()} tokens; not posted (CSV leftovers kept)${skippedNote}`,
    )
    await maybeCleanupBrowserExports(browserExports, 'dry-run')
    return
  }

  const cronSecret = process.env.CRON_SECRET
  if (!cronSecret) {
    throw new Error('CRON_SECRET is required to authenticate the ingest push')
  }
  const response = await http.post(`${ingestUrl}${INGEST_PATH}`, {
    headers: { authorization: `Bearer ${cronSecret}` },
    json: { host: '', rows },
    timeout: 60_000,
  })
  if (!response.ok) {
    await maybeCleanupBrowserExports(browserExports, 'post-failed')
    throw new Error(`ingest POST failed with ${response.status}: ${await response.text()}`)
  }
  const accepted = z
    .object({ accepted: z.number(), runId: z.string().min(1).optional() })
    .parse(await response.json())
  console.log(
    `pushed ${rows.length} cursor (date, model) rows; ${tokens.toLocaleString()} tokens; server accepted ${accepted.accepted} rows (run ${accepted.runId ?? 'none'})${skippedNote}`,
  )
  if (!accepted.runId) {
    await maybeCleanupBrowserExports(browserExports, 'ingest-confirmed')
    return
  }
  for (let attempt = 0; attempt < 30; attempt += 1) {
    await delay(2000)
    const poll = await http.get(`${ingestUrl}${INGEST_PATH}?runId=${accepted.runId}`, {
      headers: { authorization: `Bearer ${cronSecret}` },
    })
    if (poll.status === 202) {
      continue
    }
    if (!poll.ok) {
      await maybeCleanupBrowserExports(browserExports, 'workflow-failed')
      throw new Error(`ingest workflow failed: ${poll.status}: ${await poll.text()}`)
    }
    console.log(`ingest confirmed: ${JSON.stringify(await poll.json())}`)
    await maybeCleanupBrowserExports(browserExports, 'ingest-confirmed')
    return
  }
  await maybeCleanupBrowserExports(browserExports, 'workflow-failed')
  throw new Error('ingest workflow did not settle within 60s')
}

if (import.meta.main) {
  await run()
}
