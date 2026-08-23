import { expect, test } from '@playwright/test';
import {
  assertNoLoginError,
  captureScreenshot,
  clickLogin,
  requiredEnv,
  fillFirstVisible,
} from './helpers';

test('APEX development workspace login works', async ({ page }, testInfo) => {
  const workspace = process.env.APEX_WORKSPACE ?? 'SANDBOX';
  const username = process.env.APEX_WORKSPACE_USER ?? 'ADMIN';
  const password = requiredEnv(
    'APEX_WORKSPACE_PASSWORD',
  );
  const path = process.env.APEX_WORKSPACE_PATH ?? '/ords/apex';
  const successText = process.env.APEX_WORKSPACE_SUCCESS_TEXT ?? 'App Builder';

  await test.step('Open APEX workspace login page', async () => {
    await page.goto(path);
    await captureScreenshot(
      page,
      testInfo,
      '01-workspace-login-page.png',
      'APEX workspace login page',
    );
  });

  await test.step('Enter workspace credentials', async () => {
    const textInputs = page.locator('input:not([type]), input[type="text"]');

    await fillFirstVisible(
      [
        page.getByLabel(/workspace/i),
        page.getByPlaceholder(/workspace/i),
        textInputs.nth(0),
      ],
      workspace,
      'workspace',
    );

    await fillFirstVisible(
      [
        page.getByLabel(/username/i),
        page.getByPlaceholder(/username/i),
        textInputs.nth(1),
      ],
      username,
      'workspace username',
    );

    await fillFirstVisible(
      [
        page.getByLabel(/password/i),
        page.getByPlaceholder(/password/i),
        page.locator('input[type="password"]'),
      ],
      password,
      'workspace password',
    );
  });

  await test.step('Sign in to APEX workspace', async () => {
    await clickLogin(page);
    await assertNoLoginError(page);

    await expect(
      page.getByText(new RegExp(successText, 'i')).first(),
    ).toBeVisible({ timeout: 60_000 });

    await captureScreenshot(
      page,
      testInfo,
      '02-workspace-home-page.png',
      'APEX workspace home page',
    );
  });
});
