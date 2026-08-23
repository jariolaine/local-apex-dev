import { expect, test } from '@playwright/test';
import {
  assertNoLoginError,
  captureScreenshot,
  clickLogin,
  requiredEnv,
  fillUsernamePassword,
} from './helpers';

test('APEX Administration Service login works', async ({ page }, testInfo) => {
  const username = process.env.APEX_ADMIN_USER ?? 'ADMIN';
  const password = requiredEnv('APEX_ADMIN_PASSWORD',);
  const path = process.env.APEX_ADMIN_PATH ?? '/ords/apex_admin';
  const successText = process.env.APEX_ADMIN_SUCCESS_TEXT ?? 'Administration Services';

  await test.step('Open Administration Services login page', async () => {
    await page.goto(path);
    await captureScreenshot(
      page,
      testInfo,
      '01-admin-login-page.png',
      'Administration Services login page',
    );
  });

  await test.step(
    'Enter administrator credentials',
    async () => {
      await fillUsernamePassword(
        page,
        username,
        password,
        'APEX administrator',
      );
    }
  );

  await test.step('Sign in to Administration Services', async () => {
    await clickLogin(page);
    await assertNoLoginError(page);

    await expect(
      page.getByText(new RegExp(successText, 'i')).first(),
    ).toBeVisible({ timeout: 60_000 });

    await captureScreenshot(
      page,
      testInfo,
      '02-admin-home-page.png',
      'Administration Services home page',
    );
  });
});
