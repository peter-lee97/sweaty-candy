import Phaser from 'phaser';

console.log('Phaser loaded:', Phaser);

window.Phaser = Phaser;

// Load the rest of the app
import('./main.js');