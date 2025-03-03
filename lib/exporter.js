import pkg from 'pg';
const { Pool } = pkg;
import { fileExists, writeToFile, generateTableSQL, generateDartModel } from './utils/files.js';
import path from 'path';
import fs from 'fs-extra';

export class DatabaseExporter {
  constructor(config) {
    this.supabaseUrl = config.supabaseUrl;
    this.supabaseKey = config.supabaseKey;
    this.outputDir = config.outputDir || './exported_database';
    this.dartOutputDir = config.dartOutputDir || 'lib/models';
    this.verbose = config.verbose || false;
    this.schemaOnly = config.schemaOnly || false;
    this.tables = config.tables || null;
    this.stats = {
      types: 0,
      tables: 0,
      functions: 0,
      triggers: 0
    };
  }

  /**
   * Log message if verbose mode is enabled
   */
  log(message) {
    if (this.verbose) {
      console.log(message);
    }
  }

  /**
   * Initialize PostgreSQL pool
   */
  initializePool() {
    return new Pool({
      connectionString: process.env.DATABASE_URL || 'postgresql://postgres:postgres@localhost:54322/postgres'
    });
  }

  /**
   * Export database schema
   */
  async export() {
    try {
      this.log('Initializing export...');
      
      // Create output directories
      await fs.ensureDir(this.outputDir);
      
      // Initialize database pool
      const pool = this.initializePool();
      
      // Export types
      await this.exportTypes(pool);
      
      // Export tables
      await this.exportTables(pool);
      
      // Export functions
      await this.exportFunctions(pool);
      
      // Export triggers
      await this.exportTriggers(pool);
      
      // Export to Dart if enabled
      if (this.dartOutputDir) {
        console.log('⠼ Exporting database schema to Dart models...');
        
        try {
          // Create output directory if it doesn't exist
          await fs.ensureDir(this.dartOutputDir);
          
          // Get all tables
          const tablesResult = await pool.query(
            'SELECT table_name FROM information_schema.tables WHERE table_schema = $1',
            ['public']
          );
          
          // Export each table to a Dart model
          for (const table of tablesResult.rows) {
            process.stdout.write(`\rGenerating Dart model for: ${table.table_name}`);
            
            const constraintsResult = await pool.query(
              'SELECT get_table_constraints($1) as constraints',
              [table.table_name]
            );
            const constraints = constraintsResult.rows[0].constraints || [];
            
            const columnsResult = await pool.query(
              'SELECT get_column_definitions($1) as columns',
              [table.table_name]
            );
            const columns = columnsResult.rows[0].columns || [];
            
            const dartCode = generateDartModel(table.table_name, columns, constraints);
            const dartFilePath = path.join(this.dartOutputDir, `${table.table_name}.dart`);
            
            await writeToFile(dartFilePath, dartCode);
          }
          
          console.log('\n✔ Dart export completed successfully!\n');
          console.log('Dart export statistics:');
          console.log(`  Models generated: ${tablesResult.rows.length}\n`);
          console.log(`Dart output directory: ${this.dartOutputDir}\n`);
          
        } catch (error) {
          console.error('\n✖ Dart export failed:', error.message);
          throw error;
        }
      }
      
      // Close database pool
      await pool.end();
      
      console.log('\nExport statistics:');
      console.log(`  Types: ${this.stats.types}`);
      console.log(`  Tables: ${this.stats.tables}`);
      console.log(`  Functions: ${this.stats.functions}`);
      console.log(`  Triggers: ${this.stats.triggers}\n`);
      console.log(`Output directory: ${path.resolve(this.outputDir)}\n`);
      
    } catch (error) {
      console.error('Export failed:', error.message);
      throw error;
    }
  }

  /**
   * Export custom types
   */
  async exportTypes(pool) {
    this.log('Exporting custom types...');
    const typesResult = await pool.query('SELECT * FROM get_types()');
    const types = typesResult.rows[0].get_types || [];
    
    if (types.length > 0) {
      let typesSql = '-- Custom types\n\n';
      types.forEach(type => {
        typesSql += `CREATE TYPE ${type.name} AS ENUM (\n`;
        typesSql += type.values.map(v => `  '${v}'`).join(',\n');
        typesSql += '\n);\n\n';
      });
      await writeToFile(path.join(this.outputDir, '01_types.sql'), typesSql);
      this.stats.types = types.length;
    }
  }

  /**
   * Export tables with constraints
   */
  async exportTables(pool) {
    // Get list of tables
    const tablesResult = await pool.query(`
      SELECT table_name
      FROM information_schema.tables
      WHERE table_schema = 'public'
      AND table_type = 'BASE TABLE'
      ${this.tables ? 'AND table_name = ANY($1)' : ''}
      ORDER BY table_name
    `, this.tables ? [this.tables] : []);

    let tablesSql = '-- Tables with constraints\n\n';
    
    for (const table of tablesResult.rows) {
      this.log(`Processing table: ${table.table_name}`);
      
      // Get constraints
      const constraintsResult = await pool.query(
        'SELECT * FROM get_table_constraints($1)',
        [table.table_name]
      );
      const constraints = constraintsResult.rows[0].get_table_constraints || [];
      
      // Get column definitions
      const columnsResult = await pool.query(
        'SELECT * FROM get_column_definitions($1)',
        [table.table_name]
      );
      const columns = columnsResult.rows[0].get_column_definitions || [];
      
      // Generate CREATE TABLE statement
      tablesSql += generateTableSQL(table.table_name, columns, constraints);
      tablesSql += '\n';
    }

    await writeToFile(path.join(this.outputDir, '02_tables.sql'), tablesSql);
    this.stats.tables = tablesResult.rows.length;
  }

  /**
   * Export functions
   */
  async exportFunctions(pool) {
    this.log('Exporting functions...');
    const functionsResult = await pool.query('SELECT * FROM get_functions()');
    const functions = functionsResult.rows[0].get_functions || [];
    
    if (functions.length > 0) {
      let functionsSql = '-- Functions\n\n';
      functions.forEach(func => {
        functionsSql += `${func.definition}\n\n`;
      });
      await writeToFile(path.join(this.outputDir, '03_functions.sql'), functionsSql);
      this.stats.functions = functions.length;
    }
  }

  /**
   * Export triggers
   */
  async exportTriggers(pool) {
    this.log('Exporting triggers...');
    const triggersResult = await pool.query('SELECT * FROM get_triggers()');
    const triggers = triggersResult.rows[0].get_triggers || [];
    
    if (triggers.length > 0) {
      let triggersSql = '-- Triggers\n\n';
      triggers.forEach(trigger => {
        triggersSql += `${trigger.definition};\n\n`;
      });
      await writeToFile(path.join(this.outputDir, '04_triggers.sql'), triggersSql);
      this.stats.triggers = triggers.length;
    }
  }
} 