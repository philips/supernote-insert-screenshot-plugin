import {PluginCommAPI, PluginNoteAPI} from 'sn-plugin-lib';
import {ensureFileReadPermission, ensureFileWritePermission} from './permissions';

export interface InsertResult {
  success: boolean;
  message: string;
}

interface APIResponse<T> {
  success: boolean;
  result?: T;
  error?: {message?: string};
}

async function currentNotePath(): Promise<string | null> {
  const res = (await PluginCommAPI.getCurrentFilePath()) as unknown as APIResponse<string>;
  console.log('[insert-screenshot] getCurrentFilePath', JSON.stringify(res));
  if (!res || !res.success || !res.result) {
    return null;
  }
  return res.result;
}

export async function ensurePermissions(): Promise<InsertResult | null> {
  if (!(await ensureFileReadPermission())) {
    return {success: false, message: 'File read access is required to find your screenshot.'};
  }
  if (!(await ensureFileWritePermission())) {
    return {success: false, message: 'File write access is required to insert the screenshot.'};
  }
  return null;
}

export async function insertImageAtPath(path: string): Promise<InsertResult> {
  const permissionError = await ensurePermissions();
  if (permissionError) {
    return permissionError;
  }

  const notePath = await currentNotePath();
  if (!notePath) {
    return {success: false, message: 'No note is currently open.'};
  }
  if (!notePath.toLowerCase().endsWith('.note')) {
    return {success: false, message: 'Open a Supernote note (.note) to insert a screenshot.'};
  }

  try {
    await PluginNoteAPI.saveCurrentNote();
  } catch (e) {
    console.error('[insert-screenshot] saveCurrentNote failed', e);
  }

  console.log('[insert-screenshot] insertImage', path);
  const res = (await PluginNoteAPI.insertImage(path)) as unknown as APIResponse<boolean>;
  console.log('[insert-screenshot] insertImage result', JSON.stringify(res));
  if (!res || !res.success || !res.result) {
    return {
      success: false,
      message: res?.error?.message ?? 'Could not insert the screenshot (insertImage failed).',
    };
  }

  try {
    await PluginCommAPI.reloadFile();
  } catch (e) {
    console.error('[insert-screenshot] reloadFile failed', e);
  }

  return {success: true, message: 'Screenshot inserted.'};
}
