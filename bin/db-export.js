#!/usr/bin/env node

import { Command } from 'commander';
import { DatabaseExporter } from '../lib/exporter.js';
import dotenv from 'dotenv';
import path from 'path';

// Load environment variables
dotenv.config();

const program = new Command();

program
  .name('supabase-dart-exporter')
  .description('Export Supabase database schema to SQL files and Dart models')
  .version('1.0.6')
  .option('-o, --output <dir>', 'Output directory for SQL files', './exported_database')
  .option('-d, --dart', 'Generate Dart models', false)
  .option('--dart-output <dir>', 'Output directory for Dart models', 'lib/models')
  .option('-v, --verbose', 'Enable verbose logging', false)
  .option('-s, --schema-only', 'Export schema only (no data)', false)
  .option('-t, --tables <tables...>', 'Specific tables to export')
  .parse(process.argv);

const options = program.opts();

// Create exporter instance
const exporter = new DatabaseExporter({
  supabaseUrl: process.env.SUPABASE_URL,
  supabaseKey: process.env.SUPABASE_SERVICE_KEY,
  outputDir: options.output,
  dartOutputDir: options.dart ? options.dartOutput : null,
  verbose: options.verbose,
  schemaOnly: options.schemaOnly,
  tables: options.tables
});

// Run export
try {
  await exporter.export();
  console.log('✔ Export completed successfully!');
} catch (error) {
  console.error('✖ Export failed\n');
  console.error('Error details:');
  console.error(error);
  process.exit(1);
}