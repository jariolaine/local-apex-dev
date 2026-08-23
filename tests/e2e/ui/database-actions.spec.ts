import { expect, Page, test } from '@playwright/test';

import {
  assertNoLoginError,
  captureScreenshot,
  clickLogin,
  fillUsernamePassword,
  requiredEnv,
} from './helpers';

async function waitForDatabaseActionsSignInPage(
  page: Page,
): Promise<void> {
  // Database Actions renders the sign-in form behind an initial full-page
  // loader. Wait for that loader to disappear before capturing the login
  // milestone screenshot.
  await expect(
    page.locator(
      '.sdw-widget-loading.initial-css-loader',
    ),
  ).toBeHidden({
    timeout: 60_000,
  });

  await expect(
    page.getByRole('heading', {
      name: /^Sign-in$/i,
    }),
  ).toBeVisible();

  await expect(
    page.getByRole('textbox', {
      name: /^Username$/i,
    }),
  ).toBeVisible();

  await expect(
    page.getByRole('textbox', {
      name: /^Password$/i,
    }),
  ).toBeVisible();
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}

async function dismissOptionalDialogs(page: Page): Promise<void> {
  const darkThemeHeading = page.getByRole('heading', {
    name: /Introducing Dark Theme/i,
  });

  if (await darkThemeHeading.isVisible().catch(() => false)) {
    const doneButton = page.getByRole('button', {
      name: /^Done$/i,
    });

    if (await doneButton.isVisible().catch(() => false)) {
      await doneButton.click();
    }
  }
}

async function assertDatabaseActionsLaunchpad(
  page: Page,
  username: string,
): Promise<void> {
  const developmentTab = page.getByRole('tab', {
    name: /^Development$/i,
  });

  await expect(developmentTab).toBeVisible({
    timeout: 60_000,
  });

  await expect(developmentTab).toHaveAttribute(
    'aria-selected',
    'true',
  );

  const escapedUsername = escapeRegExp(username);

  await expect(
    page.getByRole('button', {
      name: new RegExp(
        `^${escapedUsername}\\s+User Menu$`,
        'i',
      ),
    }),
  ).toBeVisible({
    timeout: 60_000,
  });
}

test('Oracle Database Actions login works', async ({
  page,
}, testInfo) => {

  const username = requiredEnv(
    'DATABASE_ACTIONS_USER',
  );
  const password = requiredEnv(
    'DATABASE_ACTIONS_PASSWORD',
  );

  // ORDS exposes Database Actions under the lowercase schema alias.
  // Keep the original username for authentication and lowercase only the URL path.
  const databaseActionsPath =
    process.env.DATABASE_ACTIONS_PATH ??
    `/ords/${username.toLowerCase()}/_sdw/`;

  await test.step(
    'Open Database Actions sign-in page',
    async () => {
      await page.goto(databaseActionsPath);

      await waitForDatabaseActionsSignInPage(page);

      await captureScreenshot(
        page,
        testInfo,
        '01-database-actions-login-page.png',
        'Database Actions sign-in page',
      );
    },
  );

  await test.step(
    'Enter Database Actions credentials',
    async () => {
      await fillUsernamePassword(
        page,
        username,
        password,
        'Database Actions',
      );
    },
  );

  await test.step(
    'Sign in to Database Actions',
    async () => {
      await clickLogin(page);

      await assertNoLoginError(page);

      await assertDatabaseActionsLaunchpad(
        page,
        username,
      );
    },
  );

  await test.step(
    'Verify Database Actions Launchpad',
    async () => {
      await dismissOptionalDialogs(page);

      await captureScreenshot(
        page,
        testInfo,
        '02-database-actions-launchpad.png',
        'Database Actions Launchpad',
      );
    },
  );
});