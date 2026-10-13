package com.insertscreenshot;

import android.graphics.Bitmap;
import android.graphics.BitmapFactory;

import com.facebook.react.bridge.Arguments;
import com.facebook.react.bridge.Promise;
import com.facebook.react.bridge.ReactApplicationContext;
import com.facebook.react.bridge.ReactContextBaseJavaModule;
import com.facebook.react.bridge.ReactMethod;
import com.facebook.react.bridge.WritableMap;

import java.io.File;
import java.io.FileOutputStream;

public final class ImageCropModule extends ReactContextBaseJavaModule {
  ImageCropModule(ReactApplicationContext context) {
    super(context);
  }

  @Override
  public String getName() {
    return "ImageCrop";
  }

  @ReactMethod
  public void imageSize(String srcPath, Promise promise) {
    try {
      BitmapFactory.Options bounds = new BitmapFactory.Options();
      bounds.inJustDecodeBounds = true;
      BitmapFactory.decodeFile(srcPath, bounds);
      if (bounds.outWidth <= 0 || bounds.outHeight <= 0) {
        promise.reject("SIZE", "could not read image dimensions: " + srcPath);
        return;
      }
      WritableMap result = Arguments.createMap();
      result.putInt("width", bounds.outWidth);
      result.putInt("height", bounds.outHeight);
      promise.resolve(result);
    } catch (Exception error) {
      promise.reject("SIZE", error.getMessage(), error);
    }
  }

  @ReactMethod
  public void crop(String srcPath, int x, int y, int width, int height, Promise promise) {
    Bitmap full = null;
    Bitmap cropped = null;
    try {
      BitmapFactory.Options bounds = new BitmapFactory.Options();
      bounds.inJustDecodeBounds = true;
      BitmapFactory.decodeFile(srcPath, bounds);
      int srcW = bounds.outWidth;
      int srcH = bounds.outHeight;
      if (srcW <= 0 || srcH <= 0) {
        promise.reject("CROP", "could not decode image: " + srcPath);
        return;
      }

      int cx = Math.max(0, Math.min(x, srcW - 1));
      int cy = Math.max(0, Math.min(y, srcH - 1));
      int cw = Math.max(1, Math.min(width, srcW - cx));
      int ch = Math.max(1, Math.min(height, srcH - cy));

      full = BitmapFactory.decodeFile(srcPath);
      if (full == null) {
        promise.reject("CROP", "bitmap decode returned null: " + srcPath);
        return;
      }
      cropped = Bitmap.createBitmap(full, cx, cy, cw, ch);

      File outDir = new File(getReactApplicationContext().getCacheDir(), "insert-screenshot");
      if (!outDir.exists() && !outDir.mkdirs()) {
        promise.reject("CROP", "could not create output directory");
        return;
      }
      File output = new File(outDir, "crop-" + System.currentTimeMillis() + ".png");
      try (FileOutputStream stream = new FileOutputStream(output)) {
        cropped.compress(Bitmap.CompressFormat.PNG, 100, stream);
        stream.flush();
      }
      promise.resolve(output.getAbsolutePath());
    } catch (Exception error) {
      promise.reject("CROP", error.getMessage(), error);
    } finally {
      if (cropped != null && cropped != full) {
        cropped.recycle();
      }
      if (full != null) {
        full.recycle();
      }
    }
  }
}
