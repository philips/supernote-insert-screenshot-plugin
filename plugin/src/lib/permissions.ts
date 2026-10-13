import {PluginManager} from 'sn-plugin-lib';

const FILE_READ_PERMISSION = 'plugin.permission.FILE:READ';
const FILE_WRITE_PERMISSION = 'plugin.permission.FILE:WRITE';

async function ensure(permission: string, rationale: string): Promise<boolean> {
  const has = await PluginManager.hasPermission(permission);
  if (has === 1) {
    return true;
  }
  const result = await PluginManager.requestPermission(permission, rationale);
  return result === 1 || result === 2;
}

export function ensureFileReadPermission(): Promise<boolean> {
  return ensure(
    FILE_READ_PERMISSION,
    'Insert Screenshot needs file read access to find your most recent screenshot.',
  );
}

export function ensureFileWritePermission(): Promise<boolean> {
  return ensure(
    FILE_WRITE_PERMISSION,
    'Insert Screenshot needs file write access to add the screenshot to your note.',
  );
}
