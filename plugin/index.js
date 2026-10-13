import {AppRegistry, Image, DeviceEventEmitter} from 'react-native';
import App from './App';
import {name as appName} from './app.json';
import {PluginManager} from 'sn-plugin-lib';

export const BUTTON_EVENT = 'insertScreenshotButton';

AppRegistry.registerComponent(appName, () => App);

PluginManager.init();

PluginManager.registerButton(1, ['NOTE'], {
  id: 100,
  name: 'Insert Screenshot',
  icon: Image.resolveAssetSource(require('./assets/icon.png')).uri,
  showType: 1,
});

PluginManager.registerButtonListener({
  onButtonPress() {
    DeviceEventEmitter.emit(BUTTON_EVENT);
  },
});
