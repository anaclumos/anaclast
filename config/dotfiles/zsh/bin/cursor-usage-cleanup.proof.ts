import { access, constants, mkdtemp, readFile, unlink, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import path from 'node:path'

import {
  maybeCleanupBrowserExports,
  parseCursorUsageCsv,
  requireAggregatedCursorCsv,
  shouldCleanupBrowserExports,
  SourceUnavailableError,
} from './cursor-usage-push.ts'

const exists = async (filePath: string): Promise<boolean> => {
  try {
    await access(filePath, constants.F_OK)
    return true
  } catch {
    return false
  }
}

const assert = (condition: boolean, message: string): void => {
  if (!condition) {
    throw new Error(message)
  }
}

const SAMPLE_CSV = `Date,Kind,Model,Input (w/ Cache Write),Input (w/o Cache Write),Cache Read,Output Tokens,Total Tokens,Cost
2026-07-30T12:00:00.000Z,Included,model-a,10,100,50,20,180,Included
2026-07-30T13:00:00.000Z,On-Demand,model-a,0,200,0,30,230,1.25
`

const run = async () => {
  const pushSource = await readFile(path.join(import.meta.dir, 'cursor-usage-push.ts'), 'utf-8')
  assert(
    !pushSource.includes('CURSOR_USAGE_PROOF'),
    'production cursor-usage-push.ts must not contain CURSOR_USAGE_PROOF',
  )
  assert(!pushSource.includes('ssh'), 'production must not ssh: sources are local Chrome CSVs only')
  assert(!pushSource.includes('scp'), 'production must not scp: sources are local Chrome CSVs only')
  assert(
    !pushSource.includes('CURSOR_MANAGEMENT_KEY'),
    'production must not use the Team Admin API key',
  )
  assert(
    pushSource.includes(
      "REQUIRED_CHROME_PROFILES = ['anaclumos', 'wondermaxxing', 'Starcovery', 'twelvelabs.io']",
    ),
    'production Chrome profile guard constant missing',
  )
  assert(
    pushSource.includes('a partial list would REPLACE-wipe omitted accounts'),
    'production required-list REPLACE guard missing',
  )
  assert(
    pushSource.includes("maybeCleanupBrowserExports(browserExports, 'ingest-confirmed')"),
    'production must cleanup only via ingest-confirmed outcome',
  )
  assert(
    pushSource.includes("maybeCleanupBrowserExports(browserExports, 'post-failed')"),
    'production must gate failed POST through post-failed (no delete)',
  )
  console.log('PROOF_NO_PRODUCTION_PROOF_BYPASS=ok')

  let emptyError: unknown = null
  try {
    requireAggregatedCursorCsv('', 'proof')
  } catch (error) {
    emptyError = error
  }
  assert(emptyError instanceof SourceUnavailableError, 'empty CSV must be unavailability (skip class)')
  let headerOnlyError: unknown = null
  try {
    requireAggregatedCursorCsv(SAMPLE_CSV.split('\n')[0] + '\n', 'proof')
  } catch (error) {
    headerOnlyError = error
  }
  assert(
    headerOnlyError instanceof SourceUnavailableError,
    'header-only CSV must be unavailability (skip class)',
  )
  const aggregated = requireAggregatedCursorCsv(SAMPLE_CSV, 'proof')
  assert(aggregated.length === 1, 'sample CSV must aggregate to one (date, model) row')
  assert(aggregated[0].inputTokens === 360, 'cache read/write tokens must fold into input')
  assert(aggregated[0].outputTokens === 50, 'output tokens must sum across events')
  assert(aggregated[0].costUsd === 1.25, 'Included must not count as spend; charged rows must')
  assert(aggregated[0].requestCount === 2, 'request count must sum across events')
  let badCostError: unknown = null
  try {
    parseCursorUsageCsv(SAMPLE_CSV.replace('1.25', 'USD 1.25'))
  } catch (error) {
    badCostError = error
  }
  assert(
    badCostError instanceof Error && !(badCostError instanceof SourceUnavailableError),
    'unrecognized Cost must abort (parse class), never skip',
  )
  console.log('PROOF_CSV_PARSE_CLASSES=ok')

  assert(shouldCleanupBrowserExports('post-failed') === false, 'post-failed must not cleanup')
  assert(shouldCleanupBrowserExports('ingest-confirmed') === true, 'ingest-confirmed must cleanup')

  const dir = await mkdtemp(path.join(tmpdir(), 'cursor-usage-cleanup-proof-'))
  const csvPath = path.join(dir, 'cursor-usage-latest.csv')
  await writeFile(csvPath, 'proof-csv-bytes', 'utf-8')
  const browserExports = [
    {
      cleanup: async () => {
        await unlink(csvPath)
      },
    },
  ]

  await maybeCleanupBrowserExports(browserExports, 'post-failed')
  assert(await exists(csvPath), `post-failed deleted CSV at ${csvPath}`)
  console.log('PROOF_FAIL_KEEPS_CSV=ok')
  console.log(`csv_after_failed_post=${csvPath}`)

  await maybeCleanupBrowserExports(browserExports, 'ingest-confirmed')
  assert(!(await exists(csvPath)), `ingest-confirmed left CSV at ${csvPath}`)
  console.log('PROOF_SUCCESS_CLEANS_CSV=ok')
  console.log('csv_after_confirmed_ingest=absent')

  console.log('PROOF_CURSOR_USAGE_CLEANUP=pass')
}

await run()
