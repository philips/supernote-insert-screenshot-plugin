jest.mock('sn-plugin-lib', () => ({
  FileUtils: {listFiles: jest.fn()},
}));

import {FileUtils} from 'sn-plugin-lib';
import {listScreenshots, mostRecentScreenshot, SCREENSHOT_DIR} from '../screenshots';

const listFiles = FileUtils.listFiles as jest.Mock;

describe('screenshots', () => {
  beforeEach(() => listFiles.mockReset());

  it('returns png files sorted newest-first by timestamp name', async () => {
    listFiles.mockResolvedValue([
      {path: `${SCREENSHOT_DIR}/20261012_090000.png`},
      {path: `${SCREENSHOT_DIR}/20261012_191019.png`},
      {path: `${SCREENSHOT_DIR}/notes.txt`},
      {path: `${SCREENSHOT_DIR}/20261011_235959.png`},
    ]);

    const result = await listScreenshots();

    expect(result).toEqual([
      `${SCREENSHOT_DIR}/20261012_191019.png`,
      `${SCREENSHOT_DIR}/20261012_090000.png`,
      `${SCREENSHOT_DIR}/20261011_235959.png`,
    ]);
  });

  it('picks the most recent screenshot', async () => {
    listFiles.mockResolvedValue([
      {path: `${SCREENSHOT_DIR}/20261012_090000.png`},
      {path: `${SCREENSHOT_DIR}/20261012_191019.png`},
    ]);

    expect(await mostRecentScreenshot()).toBe(`${SCREENSHOT_DIR}/20261012_191019.png`);
  });

  it('returns null when there are no screenshots', async () => {
    listFiles.mockResolvedValue([{path: `${SCREENSHOT_DIR}/notes.txt`}]);

    expect(await mostRecentScreenshot()).toBeNull();
  });

  it('handles a missing or empty folder gracefully', async () => {
    listFiles.mockResolvedValue(null);

    expect(await listScreenshots()).toEqual([]);
    expect(await mostRecentScreenshot()).toBeNull();
  });
});
