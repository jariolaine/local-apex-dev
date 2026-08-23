import { defineConfig, devices } from '@playwright/test';

const outputDir = process.env.PLAYWRIGHT_OUTPUT_DIR ?? 'artifacts/output/default';
const reportDir = process.env.PLAYWRIGHT_REPORT_DIR ?? 'artifacts/report/default';

export default defineConfig({
  testDir: '.',
  testMatch: /.*\.spec\.ts/,
  timeout: 120_000,
  expect: {
    timeout: 30_000,
  },
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [
    ['line'],
    ['html', { outputFolder: reportDir, open: 'never' }],
  ],
  outputDir,
  use: {
    baseURL: process.env.ORDS_BASE_URL ?? 'http://ords:8080',
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
    ...devices['Desktop Chrome'],
  },
});
