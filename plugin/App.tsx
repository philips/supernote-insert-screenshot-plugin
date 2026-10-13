import React, {useEffect, useMemo, useRef, useState} from 'react';
import {
  View,
  Text,
  Image,
  Pressable,
  ScrollView,
  StyleSheet,
  LayoutChangeEvent,
  GestureResponderEvent,
  useWindowDimensions,
  DeviceEventEmitter,
} from 'react-native';
import {PluginManager} from 'sn-plugin-lib';
import {mostRecentScreenshot, listScreenshots} from './src/lib/screenshots';
import {insertImageAtPath, ensurePermissions} from './src/lib/insertScreenshot';
import {imageSize, cropImage} from './src/lib/imageCrop';

interface Point {
  x: number;
  y: number;
}

const MIN_CROP = 8;
const MARKER = 40;

function clamp(value: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, value));
}

function basename(p: string): string {
  const i = p.lastIndexOf('/');
  return i >= 0 ? p.slice(i + 1) : p;
}

export default function App(): React.JSX.Element {
  const {width: windowWidth} = useWindowDimensions();
  const [screen, setScreen] = useState<'crop' | 'pick'>('crop');
  const [list, setList] = useState<string[]>([]);
  const [path, setPath] = useState<string | null>(null);
  const [src, setSrc] = useState<{width: number; height: number} | null>(null);
  const [container, setContainer] = useState<{w: number; h: number} | null>(null);
  const [points, setPoints] = useState<Point[]>([]);
  const [status, setStatus] = useState<string>('Loading screenshot...');
  const [busy, setBusy] = useState<boolean>(true);
  const busyRef = useRef<boolean>(true);

  const setBusyFlag = (value: boolean) => {
    busyRef.current = value;
    setBusy(value);
  };

  const close = () => PluginManager.closePluginView();

  const loadImage = async (p: string) => {
    setBusyFlag(true);
    setStatus('Loading screenshot...');
    setPoints([]);
    try {
      const size = await imageSize(p);
      setPath(p);
      setSrc(size);
      setStatus('');
    } catch (e: any) {
      console.error('[insert-screenshot] imageSize failed', e);
      setStatus('Error: ' + (e?.message ?? String(e)));
    } finally {
      setBusyFlag(false);
    }
  };

  const start = async () => {
    setScreen('crop');
    setPoints([]);
    setBusyFlag(true);
    setStatus('Loading screenshot...');
    const permissionError = await ensurePermissions();
    if (permissionError) {
      setStatus(permissionError.message);
      setBusyFlag(false);
      return;
    }
    const recent = await mostRecentScreenshot();
    if (!recent) {
      setStatus('No screenshots found in the SCREENSHOT folder.');
      setBusyFlag(false);
      return;
    }
    await loadImage(recent);
  };

  useEffect(() => {
    start();
    const sub = DeviceEventEmitter.addListener('insertScreenshotButton', start);
    return () => sub.remove();
  }, []);

  const display = useMemo(() => {
    if (!src || !container) {
      return null;
    }
    const scale = Math.min(container.w / src.width, container.h / src.height);
    const dispW = src.width * scale;
    const dispH = src.height * scale;
    const offX = (container.w - dispW) / 2;
    const offY = (container.h - dispH) / 2;
    return {scale, dispW, dispH, offX, offY};
  }, [src, container]);

  const crop = useMemo(() => {
    if (!display) {
      return null;
    }
    if (points.length === 2) {
      const [a, b] = points;
      return {
        left: Math.min(a.x, b.x),
        top: Math.min(a.y, b.y),
        width: Math.abs(a.x - b.x),
        height: Math.abs(a.y - b.y),
      };
    }
    return {left: display.offX, top: display.offY, width: display.dispW, height: display.dispH};
  }, [points, display]);

  const onBodyLayout = (e: LayoutChangeEvent) => {
    const {width, height} = e.nativeEvent.layout;
    setContainer({w: width, h: height});
  };

  const handleTap = (evt: GestureResponderEvent) => {
    if (!display || busyRef.current) {
      return;
    }
    const x = clamp(evt.nativeEvent.locationX, display.offX, display.offX + display.dispW);
    const y = clamp(evt.nativeEvent.locationY, display.offY, display.offY + display.dispH);
    setPoints(prev => (prev.length === 1 ? [prev[0], {x, y}] : [{x, y}]));
  };

  const resetCrop = () => setPoints([]);

  const insertCurrent = async () => {
    if (!path || !display || !crop) {
      return;
    }
    if (crop.width < MIN_CROP || crop.height < MIN_CROP) {
      setStatus('Crop area is too small.');
      return;
    }
    setBusyFlag(true);
    setStatus('Inserting...');
    try {
      const sx = (crop.left - display.offX) / display.scale;
      const sy = (crop.top - display.offY) / display.scale;
      const sw = crop.width / display.scale;
      const sh = crop.height / display.scale;
      const croppedPath = await cropImage(path, sx, sy, sw, sh);
      const result = await insertImageAtPath(croppedPath);
      if (result.success) {
        close();
      } else {
        setStatus(result.message);
        setBusyFlag(false);
      }
    } catch (e: any) {
      console.error('[insert-screenshot] insertCurrent failed', e);
      setStatus('Error: ' + (e?.message ?? String(e)));
      setBusyFlag(false);
    }
  };

  const openPicker = async () => {
    setBusyFlag(true);
    setStatus('');
    const files = await listScreenshots();
    setList(files);
    setScreen('pick');
    setBusyFlag(false);
  };

  const pickItem = async (p: string) => {
    setScreen('crop');
    await loadImage(p);
  };

  const hint =
    points.length === 0
      ? 'Tap the top-left corner, then the bottom-right. Or Insert for the full image.'
      : points.length === 1
      ? 'Now tap the bottom-right corner.'
      : 'Crop set. Tap again to redo.';

  const Header = ({title}: {title: string}) => (
    <View style={styles.header}>
      <Pressable style={styles.closeButton} onPress={close} hitSlop={16}>
        <Text style={styles.closeIcon}>✕</Text>
      </Pressable>
      <Text style={styles.headerTitle}>{title}</Text>
      <View style={styles.closeButton} />
    </View>
  );

  if (screen === 'pick') {
    const cols = 3;
    const gap = 12;
    const tileW = Math.floor((windowWidth - 32 - gap * (cols - 1)) / cols);
    const thumbH = Math.round((tileW * 4) / 3);
    return (
      <View style={styles.root}>
        <Header title="Choose screenshot" />
        <ScrollView contentContainerStyle={styles.pickGrid}>
          {list.length === 0 ? (
            <Text style={styles.emptyText}>No screenshots found.</Text>
          ) : (
            list.map(p => (
              <Pressable key={p} style={{width: tileW}} onPress={() => pickItem(p)}>
                <Image
                  source={{uri: 'file://' + p}}
                  style={[styles.tileThumb, {width: tileW, height: thumbH}]}
                  resizeMode="contain"
                />
                <Text style={styles.tileName} numberOfLines={1}>
                  {basename(p)}
                </Text>
              </Pressable>
            ))
          )}
        </ScrollView>
      </View>
    );
  }

  return (
    <View style={styles.root}>
      <Header title="Insert Screenshot" />

      <View style={styles.toolbar}>
        <Pressable style={styles.toolButton} onPress={openPicker} disabled={busy}>
          <Text style={styles.toolButtonText}>Choose alternate screenshot</Text>
        </Pressable>
        <Pressable
          style={[styles.toolButton, styles.toolButtonPrimary]}
          onPress={insertCurrent}
          disabled={busy || !crop}>
          <Text style={[styles.toolButtonText, styles.toolButtonTextPrimary]}>
            Insert Current Screenshot
          </Text>
        </Pressable>
      </View>

      <View style={styles.hintRow}>
        <Text style={styles.hintText}>{hint}</Text>
        <Pressable style={styles.resetButton} onPress={resetCrop} disabled={busy} hitSlop={12}>
          <Text style={styles.resetText}>Reset crop</Text>
        </Pressable>
      </View>

      <View style={styles.body} onLayout={onBodyLayout}>
        {path && display ? (
          <Image
            source={{uri: 'file://' + path}}
            style={{
              position: 'absolute',
              left: display.offX,
              top: display.offY,
              width: display.dispW,
              height: display.dispH,
            }}
            resizeMode="stretch"
          />
        ) : null}

        {crop && display && points.length !== 1 ? (
          <View
            pointerEvents="none"
            style={[
              styles.cropBox,
              {left: crop.left, top: crop.top, width: crop.width, height: crop.height},
            ]}
          />
        ) : null}

        {points.map((p, i) => (
          <View
            key={i}
            pointerEvents="none"
            style={[styles.marker, {left: p.x - MARKER / 2, top: p.y - MARKER / 2}]}>
            <View style={styles.markerDot} />
          </View>
        ))}

        <View
          style={StyleSheet.absoluteFill}
          onStartShouldSetResponder={() => true}
          onResponderRelease={handleTap}
        />

        {status ? (
          <View style={styles.statusWrap} pointerEvents="none">
            <Text style={styles.statusText}>{status}</Text>
          </View>
        ) : null}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  root: {flex: 1, backgroundColor: '#ffffff'},
  header: {
    height: 72,
    backgroundColor: '#000000',
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
  },
  closeButton: {width: 56, height: 56, alignItems: 'center', justifyContent: 'center'},
  closeIcon: {color: '#ffffff', fontSize: 34, fontWeight: '300'},
  headerTitle: {color: '#ffffff', fontSize: 24, fontWeight: '600'},
  toolbar: {flexDirection: 'row', gap: 12, padding: 12},
  toolButton: {
    flex: 1,
    borderWidth: 2,
    borderColor: '#000000',
    paddingVertical: 14,
    alignItems: 'center',
    justifyContent: 'center',
  },
  toolButtonPrimary: {backgroundColor: '#000000'},
  toolButtonText: {fontSize: 18, color: '#000000'},
  toolButtonTextPrimary: {color: '#ffffff'},
  hintRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    paddingBottom: 10,
  },
  hintText: {flex: 1, fontSize: 15, color: '#000000', paddingRight: 12},
  resetButton: {borderWidth: 2, borderColor: '#000000', paddingVertical: 10, paddingHorizontal: 20},
  resetText: {fontSize: 16, color: '#000000'},
  body: {flex: 1, backgroundColor: '#e8e8e8', marginBottom: 12},
  cropBox: {position: 'absolute', borderWidth: 3, borderColor: '#000000', backgroundColor: 'rgba(0,0,0,0.04)'},
  marker: {position: 'absolute', width: MARKER, height: MARKER, alignItems: 'center', justifyContent: 'center'},
  markerDot: {
    width: 18,
    height: 18,
    borderRadius: 9,
    backgroundColor: '#ffffff',
    borderWidth: 3,
    borderColor: '#000000',
  },
  statusWrap: {position: 'absolute', top: 16, left: 0, right: 0, alignItems: 'center'},
  statusText: {fontSize: 16, color: '#000000', backgroundColor: '#ffffff', paddingHorizontal: 12, paddingVertical: 6},
  pickGrid: {padding: 16, flexDirection: 'row', flexWrap: 'wrap', gap: 12},
  tileThumb: {backgroundColor: '#e8e8e8', borderWidth: 1, borderColor: '#000000'},
  tileName: {fontSize: 11, color: '#000000', marginTop: 4, textAlign: 'center'},
  emptyText: {fontSize: 18, color: '#000000', textAlign: 'center', marginTop: 40},
});
