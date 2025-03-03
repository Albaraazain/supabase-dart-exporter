import { DatabaseExporter } from '../lib/exporter.js';
import { fileExists, readFromFile } from '../lib/utils/files.js';
import { installFunctions } from './setup.js';
import path from 'path';
import assert from 'assert';
import fs from 'fs-extra';
import { config } from 'dotenv';

// Load environment variables
config({ path: '.env.test' });

// Clean up test directory before running tests
async function cleanup(dir) {
  if (await fileExists(dir)) {
    await fs.remove(dir);
  }
}

// Verify constraint exports in SQL file
async function verifySQLConstraints(filePath) {
  const content = await readFromFile(filePath);
  const requiredConstraints = [
    'PRIMARY KEY',
    'FOREIGN KEY',
    'REFERENCES',
    'UNIQUE',
    'CHECK',
    'DEFAULT',
    'NOT NULL'
  ];

  for (const constraint of requiredConstraints) {
    if (!content.includes(constraint)) {
      throw new Error(`Missing constraint type: ${constraint}`);
    }
  }

  // Check for foreign key actions
  if (!content.includes('ON DELETE') && !content.includes('ON UPDATE')) {
    throw new Error('Missing foreign key action clauses');
  }
}

// Verify Dart model documentation
async function verifyDartDocs(modelDir) {
  const files = await fs.readdir(modelDir);
  if (files.length === 0) {
    throw new Error('No Dart models generated');
  }

  const modelContent = await readFromFile(path.join(modelDir, files[0]));
  const requiredDocs = [
    'Primary key',
    'Foreign key reference to',
    'Default:',
    'Check constraint:'
  ];

  for (const doc of requiredDocs) {
    if (!modelContent.includes(doc)) {
      throw new Error(`Missing documentation: ${doc}`);
    }
  }
}

async function runTest() {
  console.log('🧪 Running export tests...');

  try {
    // Install required functions first
    await installFunctions();
  } catch (error) {
    console.error('Failed to install test functions:', error.message);
    process.exit(1);
  }

  const testOutputDir = './test-output';
  await cleanup(testOutputDir);
  console.log('🧹 Cleaned up test directory');

  const testConfig = {
    supabaseUrl: process.env.SUPABASE_URL,
    supabaseKey: process.env.SUPABASE_SERVICE_KEY,
    outputDir: testOutputDir,
    verbose: true
  };

  try {
    // Create exporter instance
    const exporter = new DatabaseExporter(testConfig);
    
    // Run export
    console.log('📤 Running export...');
    const result = await exporter.export();
    
    // Verify output files exist
    console.log('✅ Verifying output files...');
    
    const requiredFiles = [
      '01_types.sql',
      '02_tables.sql',
      'master.sql'
    ];
    
    for (const file of requiredFiles) {
      const filePath = path.join(testOutputDir, file);
      if (!await fileExists(filePath)) {
        throw new Error(`Missing required file: ${file}`);
      }
    }
    
    // Verify constraints in tables file
    console.log('🔍 Verifying SQL constraints...');
    await verifySQLConstraints(path.join(testOutputDir, '02_tables.sql'));
    
    // Test Dart export if database URL is available
    if (process.env.DATABASE_URL) {
      console.log('📝 Testing Dart export...');
      
      const dartOutputDir = path.join(testOutputDir, 'dart');
      const dartResult = await exporter.exportToDart({
        outputDir: dartOutputDir,
        generateDocs: true,
        generateEquality: true,
        connectionString: process.env.DATABASE_URL
      });
      
      // Verify Dart model documentation
      console.log('📚 Verifying Dart model documentation...');
      await verifyDartDocs(dartOutputDir);
      
      console.log('✨ Dart export successful:', dartResult);
    }
    
    console.log('✅ All tests passed!');
    console.log(`📊 Export statistics:
      Types: ${result.stats.types}
      Tables: ${result.stats.tables}
      Functions: ${result.stats.functions}
      Triggers: ${result.stats.triggers}
    `);
    
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    process.exit(1);
  } finally {
    // Clean up test output
    await cleanup(testOutputDir);
  }
}

// Verify environment variables
if (!process.env.SUPABASE_URL || !process.env.SUPABASE_SERVICE_KEY) {
  console.error('❌ Missing required environment variables SUPABASE_URL and SUPABASE_SERVICE_KEY');
  process.exit(1);
}

// Run tests
runTest().catch(error => {
  console.error('❌ Unexpected error:', error);
  process.exit(1);
});