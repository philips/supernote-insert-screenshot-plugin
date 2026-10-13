import {NativeModules} from 'react-native';

const {ImageCrop} = NativeModules as {
  ImageCrop?: {
    imageSize(path: string): Promise<{width: number; height: number}>;
    crop(path: string, x: number, y: number, width: number, height: number): Promise<string>;
  };
};

export interface ImageSize {
  width: number;
  height: number;
}

export function isNativeCropAvailable(): boolean {
  return !!ImageCrop;
}

export async function imageSize(path: string): Promise<ImageSize> {
  if (!ImageCrop) {
    throw new Error('Native ImageCrop module is unavailable.');
  }
  return ImageCrop.imageSize(path);
}

export async function cropImage(
  path: string,
  x: number,
  y: number,
  width: number,
  height: number,
): Promise<string> {
  if (!ImageCrop) {
    throw new Error('Native ImageCrop module is unavailable.');
  }
  return ImageCrop.crop(
    path,
    Math.round(x),
    Math.round(y),
    Math.round(width),
    Math.round(height),
  );
}
