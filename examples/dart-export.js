/**
 * Example of using the Dart export functionality
 * 
 * This example demonstrates how to use the DatabaseExporter to generate
 * Dart models from your PostgreSQL database schema.
 */

import { DatabaseExporter } from '../lib/exporter.js';
import { config } from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

// Load environment variables from .env file
config();

// Get the directory of the current module
const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

// Create an instance of the DatabaseExporter
const exporter = new DatabaseExporter({
  supabaseUrl: process.env.SUPABASE_URL,
  supabaseKey: process.env.SUPABASE_SERVICE_KEY,
  outputDir: path.join(__dirname, '../output'),
  verbose: true
});

async function run() {
  try {
    console.log('Starting Dart export...');
    
    // Export database schema to Dart models
    const result = await exporter.exportToDart({
      outputDir: path.join(__dirname, '../output/dart_models'),
      generateDocs: true,
      generateEquality: true,
      connectionString: process.env.DATABASE_URL
    });
    
    console.log('Dart export completed successfully!');
    console.log(`Generated ${result.modelCount} Dart models`);
    console.log(`Output directory: ${result.outputDir}`);
    
    // Example of how to use the generated models in your Flutter app:
    console.log('\nUsage in Flutter:');
    console.log(`
// Import the generated model
import 'package:your_app/models/user.dart';

// Create a new instance
final user = User(
  id: 1,
  name: 'John Doe',
  email: 'john@example.com',
  createdAt: DateTime.now()
);

// Convert to JSON
final json = user.toJson();

// Create from JSON
final userFromJson = User.fromJson(json);

// Create a copy with modified values
final updatedUser = user.copyWith(name: 'Jane Doe');
    `);
    
  } catch (error) {
    console.error('Export failed:', error.message);
    process.exit(1);
  }
}

run(); 