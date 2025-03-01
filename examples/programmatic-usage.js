/**
 * Example of programmatic usage of the DatabaseExporter
 */
import { DatabaseExporter } from '../lib/exporter.js';
import dotenv from 'dotenv';

// Load environment variables
dotenv.config();

// Configuration
const config = {
  supabaseUrl: process.env.SUPABASE_URL,
  supabaseKey: process.env.SUPABASE_SERVICE_KEY,
  outputDir: './my-database-export',
  verbose: true,
  schemaOnly: false,
  tables: ['users', 'profiles'] // Optional: specify tables to export
};

// Create exporter instance
const exporter = new DatabaseExporter(config);

// Run the export
async function run() {
  try {
    console.log('Starting database export...');
    
    const result = await exporter.export();
    
    console.log('Export completed successfully!');
    console.log('Statistics:');
    console.log(`  Types: ${result.stats.types}`);
    console.log(`  Tables: ${result.stats.tables}`);
    console.log(`  Functions: ${result.stats.functions}`);
    console.log(`  Triggers: ${result.stats.triggers}`);
    
  } catch (error) {
    console.error('Export failed:');
    console.error(error);
    process.exit(1);
  }
}

run(); 