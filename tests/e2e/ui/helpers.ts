import { expect, Locator, Page, TestInfo } from '@playwright/test';

export function requiredEnv(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is required.`);
  }
  return value;
}

export async function captureScreenshot(
  page: Page,
  testInfo: TestInfo,
  fileName: string,
  attachmentName: string,
): Promise<void> {
  const screenshotPath = testInfo.outputPath(fileName);

  await page.screenshot({
    path: screenshotPath,
    fullPage: true,
  });

  await testInfo.attach(attachmentName, {
    path: screenshotPath,
    contentType: 'image/png',
  });
}

export async function fillFirstVisible(
  candidates: Locator[],
  value: string,
  description: string,
): Promise<void> {
  for (const locator of candidates) {
    if ((await locator.count()) === 0) continue;
    const first = locator.first();
    if (await first.isVisible().catch(() => false)) {
      await first.fill(value);
      return;
    }
  }

  throw new Error(`Could not find a visible ${description} field.`);
}

// export async function clickLogin(
//   page: Page,
// ): Promise<void> {
//   const loginButton = await findLoginButton(page);

//   await loginButton.click();
// }

export async function clickLogin(
  page: Page,
): Promise<void> {
  await page
    .getByRole('button', {
      name: /sign in|log in|login/i,
    })
    .first()
    .click({
      timeout: 60_000,
    });
}

export async function fillUsernamePassword(
  page: Page,
  username: string,
  password: string,
  description: string,
): Promise<void> {
  await fillFirstVisible(
    [
      page.getByLabel(/username|user name/i),
      page.getByPlaceholder(/username|user name/i),
      page.locator('input[type="text"]').first(),
    ],
    username,
    `${description} username`,
  );

  await fillFirstVisible(
    [
      page.getByLabel(/password/i),
      page.getByPlaceholder(/password/i),
      page.locator('input[type="password"]').first(),
    ],
    password,
    `${description} password`,
  );
}

export async function assertNoLoginError(page: Page): Promise<void> {
  await expect(page.locator('body')).not.toContainText(
    /invalid credentials|invalid login|authentication failed|incorrect password/i,
  );
}

async function findLoginButton(
  page: Page,
): Promise<Locator> {
  const candidates = [
    page.getByRole('button', {
      name: /sign in|log in|login/i,
    }),
    page.locator('button[type="submit"]'),
  ];

  for (const locator of candidates) {
    if ((await locator.count()) === 0) {
      continue;
    }

    const first = locator.first();

    if (await first.isVisible().catch(() => false)) {
      return first;
    }
  }

  throw new Error(
    'Could not find a visible login button.',
  );
}
