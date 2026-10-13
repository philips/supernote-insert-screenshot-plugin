import {FileUtils} from 'sn-plugin-lib';

export const SCREENSHOT_DIR = '/storage/emulated/0/SCREENSHOT';

const IMAGE_EXTENSIONS = ['.png'];

function basename(path: string): string {
  const idx = path.lastIndexOf('/');
  return idx >= 0 ? path.slice(idx + 1) : path;
}

function isImage(path: string): boolean {
  const lower = path.toLowerCase();
  return IMAGE_EXTENSIONS.some(ext => lower.endsWith(ext));
}

function toPath(entry: unknown, dir: string): string | null {
  let name: string | null = null;
  if (typeof entry === 'string') {
    name = entry;
  } else if (entry && typeof entry === 'object') {
    const obj = entry as Record<string, unknown>;
    const candidate = obj.path ?? obj.filePath ?? obj.name ?? obj.fileName;
    if (typeof candidate === 'string') {
      name = candidate;
    }
  }
  if (!name) {
    return null;
  }
  return name.includes('/') ? name : `${dir}/${name}`;
}

export async function listScreenshots(dir: string = SCREENSHOT_DIR): Promise<string[]> {
  let entries: unknown;
  try {
    entries = await FileUtils.listFiles(dir);
  } catch (e) {
    console.error('[insert-screenshot] listFiles failed', e);
    return [];
  }
  console.log('[insert-screenshot] listFiles raw', JSON.stringify(entries));
  if (!Array.isArray(entries)) {
    return [];
  }
  return entries
    .map(entry => toPath(entry, dir))
    .filter((path): path is string => !!path && isImage(path))
    .sort((a, b) => basename(b).localeCompare(basename(a)));
}

export async function mostRecentScreenshot(dir: string = SCREENSHOT_DIR): Promise<string | null> {
  const screenshots = await listScreenshots(dir);
  console.log('[insert-screenshot] screenshots', JSON.stringify(screenshots));
  return screenshots.length > 0 ? screenshots[0] : null;
}
