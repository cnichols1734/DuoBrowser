const { chromium } = require('playwright');
const fs = require('node:fs');
const path = require('node:path');

(async () => {
    const browser = await chromium.launch({ headless: true });
    try {
        for (const [suite, source] of [
            ['PageLayoutTests.cjs', 'PageLayout.js'],
            ['CameraAvoidanceTests.cjs', 'CameraAvoidance.js'],
            ['CameraSettlingTests.cjs', 'CameraAvoidance.js'],
        ]) {
            const context = await browser.newContext();
            const page = await context.newPage();
            try {
                const result = await require('./' + suite)(
                    page, fs.readFileSync(path.join(__dirname, '../DuoBrowser', source), 'utf8')
                );
                if (!(result.passed > 0)) throw new Error('No assertions ran: ' + suite);
                console.log(suite + ': ' + result.passed + ' checks passed');
            } finally { await context.close(); }
        }
    } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
