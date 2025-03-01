#!/usr/bin/env node

/**
 * This script helps with installing the package globally
 * It sets the executable permissions on the CLI entry point
 */

import fs from 'fs-extra';
import path from 'path';
import { exec } from 'child_process';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Path to the CLI entry point
const cliPath = path.join(__dirname, '../bin/db-export.js');

// Set executable permissions
try {
  fs.chmodSync(cliPath, '755');
  console.log('✅ Set executable permissions on CLI entry point');
} catch (error) {
  console.error('❌ Failed to set executable permissions:', error.message);
  process.exit(1);
}

// Check if the package is installed globally
exec('npm list -g @voltzy/db-export', (error, stdout) => {
  if (stdout.includes('@voltzy/db-export')) {
    console.log('✅ Package is installed globally');
    console.log('You can now run the command: db-export');
  } else {
    console.log('ℹ️ To install the package globally, run:');
    console.log('npm install -g @voltzy/db-export');
  }
});

// Verify Node.js version
const nodeVersion = process.version;
const majorVersion = parseInt(nodeVersion.slice(1).split('.')[0], 10);

if (majorVersion < 18) {
  console.warn('⚠️ Warning: This package requires Node.js 18 or higher');
  console.warn(`Current version: ${nodeVersion}`);
}

console.log('\n📚 Documentation: https://github.com/voltzy/db-export#readme'); 