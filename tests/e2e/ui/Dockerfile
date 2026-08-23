FROM mcr.microsoft.com/playwright:v1.62.0-noble

WORKDIR /tests

COPY package.json ./
RUN npm install --no-audit --no-fund

COPY . .
# Parse and register all Playwright tests during image build so syntax errors
# and broken local imports fail before the expensive E2E environment starts.
RUN npx playwright test --list

CMD ["npm", "test"]
