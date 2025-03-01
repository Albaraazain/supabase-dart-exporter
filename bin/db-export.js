#!/usr/bin/env node

import { Command } from 'commander';
import chalk from 'chalk';
import ora from 'ora';
import { config } from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';
import { DatabaseExporter } from '../lib/exporter.js';
import { readFromFile, fileExists, writeToFile } from '../lib/utils/files.js';
import { createClient } from '@supabase/supabase-js';
import { exec } from 'child_process';
import { promisify } from 'util';
import fs from 'fs-extra';

const execAsync = promisify(exec);
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Initialize CLI
const program = new Command();

// Configure CLI options
program
  .name('db-export')
  .description('Export Supabase database schema and data')
  .version('1.0.0')
  .option('-o, --output <dir>', 'output directory for exported files', './exported_database')
  .option('-e, --env <path>', 'path to .env file', '.env')
  .option('-v, --verbose', 'enable verbose logging')
  .option('--url <url>', 'Supabase project URL')
  .option('--key <key>', 'Supabase service role key')
  .option('--schema-only', 'export schema without data')
  .option('--tables <tables>', 'comma-separated list of tables to export')
  .option('--install-functions', 'install required database functions')
  .option('--dart', 'export database schema to Dart models')
  .option('--dart-output <dir>', 'output directory for Dart models (defaults to <output>/dart_models)')
  .option('--dart-no-docs', 'disable documentation generation for Dart models')
  .option('--dart-no-equality', 'disable equality methods for Dart models')
  .option('--connection-string <string>', 'PostgreSQL connection string for Dart export');

program.parse();

const options = program.opts();

// Load environment variables
const envPath = path.resolve(process.cwd(), options.env);
config({ path: envPath });

// Initialize spinner
const spinner = ora({
  text: 'Starting export process...',
  color: 'blue'
});

/**
 * Install required database functions
 */
async function installFunctions(supabaseUrl, supabaseKey) {
  try {
    spinner.start('Installing database functions...');
    
    // Get the SQL installation script
    const installScriptPath = path.join(__dirname, '../sql/install_functions.sql');
    const installScript = await readFromFile(installScriptPath);
    
    // Connect to the database
    const supabase = createClient(supabaseUrl, supabaseKey, {
      db: { schema: 'public' }
    });
    
    // Execute the installation script
    const { error } = await supabase.rpc('exec_sql', { sql: installScript });
    
    if (error) {
      // If the exec_sql function doesn't exist, we need to use psql directly
      if (error.message.includes('function exec_sql') || error.code === 'PGRST116') {
        spinner.text = 'Using psql to install functions...';
        
        // Extract connection info from URL
        const url = new URL(supabaseUrl);
        const host = url.hostname;
        const port = url.port || '5432';
        
        // Create a temporary file with the installation script
        const tempScriptPath = path.join(process.cwd(), 'temp_install_functions.sql');
        await writeToFile(tempScriptPath, installScript);
        
        // Execute with psql
        try {
          await execAsync(`PGPASSWORD=${supabaseKey} psql -h ${host} -p ${port} -U postgres -d postgres -f ${tempScriptPath}`);
          // Remove temp file
          await fs.remove(tempScriptPath);
        } catch (psqlError) {
          spinner.fail('Failed to install functions using psql');
          console.error(chalk.red(`Error: ${psqlError.message}`));
          console.log(chalk.yellow('\nPlease install the functions manually:'));
          console.log(`1. Save the content of ${installScriptPath} to a file`);
          console.log('2. Run the file using psql or the Supabase SQL editor');
          process.exit(1);
        }
      } else {
        throw error;
      }
    }
    
    spinner.succeed('Database functions installed successfully');
  } catch (error) {
    spinner.fail('Failed to install database functions');
    console.error(chalk.red(`Error: ${error.message}`));
    process.exit(1);
  }
}

async function main() {
  try {
    // Validate required configuration
    const supabaseUrl = options.url || process.env.SUPABASE_URL;
    const supabaseKey = options.key || process.env.SUPABASE_SERVICE_KEY;
    const connectionString = options.connectionString || process.env.DATABASE_URL;

    if (!supabaseUrl || !supabaseKey) {
      console.error(chalk.red('Error: Missing required configuration'));
      console.error(chalk.yellow('Please provide either:'));
      console.error('  1. SUPABASE_URL and SUPABASE_SERVICE_KEY in your .env file');
      console.error('  2. --url and --key command line arguments');
      process.exit(1);
    }

    // Install functions if requested
    if (options.installFunctions) {
      await installFunctions(supabaseUrl, supabaseKey);
      if (!options.output && !options.dart) {
        // If only installing functions, exit
        return;
      }
    }

    // Create exporter instance
    const exporter = new DatabaseExporter({
      supabaseUrl,
      supabaseKey,
      outputDir: options.output,
      verbose: options.verbose,
      schemaOnly: options.schemaOnly,
      tables: options.tables?.split(',')
    });

    // Export SQL if not only doing Dart export
    if (!options.dart || options.output) {
      // Start the export process
      spinner.start('Initializing SQL export...');
      
      // Run the export
      const result = await exporter.export();
      
      spinner.succeed(chalk.green('SQL export completed successfully!'));
      console.log(chalk.cyan('\nExport statistics:'));
      console.log(`  Types: ${result.stats.types}`);
      console.log(`  Tables: ${result.stats.tables}`);
      console.log(`  Functions: ${result.stats.functions}`);
      console.log(`  Triggers: ${result.stats.triggers}`);
      console.log(chalk.cyan('\nOutput directory:'), chalk.white(path.resolve(options.output)));
    }

    // Export to Dart if requested
    if (options.dart) {
      if (!connectionString) {
        console.warn(chalk.yellow('\nWarning: Missing DATABASE_URL for Dart export'));
        console.warn(chalk.yellow('Please provide either:'));
        console.warn('  1. DATABASE_URL in your .env file');
        console.warn('  2. --connection-string command line argument');
        
        if (!options.output) {
          process.exit(1);
        }
      } else {
        spinner.start('Exporting database schema to Dart models...');
        
        const dartOptions = {
          outputDir: options.dartOutput || path.join(options.output, 'dart_models'),
          generateDocs: !options.dartNoDocs,
          generateEquality: !options.dartNoEquality,
          connectionString
        };
        
        const dartResult = await exporter.exportToDart(dartOptions);
        
        spinner.succeed(chalk.green('Dart export completed successfully!'));
        console.log(chalk.cyan('\nDart export statistics:'));
        console.log(`  Models generated: ${dartResult.modelCount}`);
        console.log(chalk.cyan('\nDart output directory:'), chalk.white(path.resolve(dartResult.outputDir)));
      }
    }

  } catch (error) {
    spinner.fail(chalk.red('Export failed'));
    if (options.verbose) {
      console.error(chalk.red('\nError details:'));
      console.error(error);
    } else {
      console.error(chalk.red(`\nError: ${error.message}`));
      console.error(chalk.yellow('Run with --verbose for more details'));
    }
    process.exit(1);
  }
}

main().catch(error => {
  spinner.fail(chalk.red('Unexpected error'));
  console.error(error);
  process.exit(1);
});