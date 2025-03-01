import { createClient } from '@supabase/supabase-js';
import chalk from 'chalk';
import path from 'path';
import { fileExists, writeToFile } from './utils/files.js';
import {
  formatCreateTable,
  formatInsert,
  formatCreateEnum,
  formatCreateFunction,
  formatCreateTrigger
} from './utils/sql.js';
import { convertDbToDart } from './utils/dart.js';

export class DatabaseExporter {
  constructor(config) {
    this.config = {
      supabaseUrl: '',
      supabaseKey: '',
      outputDir: './exported_database',
      verbose: false,
      schemaOnly: false,
      tables: null,
      ...config
    };

    this.supabase = createClient(this.config.supabaseUrl, this.config.supabaseKey, {
      db: { schema: 'public' }
    });

    this.log = this.config.verbose
      ? (message) => console.log(chalk.blue(message))
      : () => {};
  }

  /**
   * Fetches custom types from the database
   */
  async getCustomTypes() {
    this.log('Fetching custom types...');
    const { data, error } = await this.supabase
      .from('get_enum_types')
      .select('type_name, definition');
    
    if (error) throw new Error(`Failed to fetch custom types: ${error.message}`);
    return data || [];
  }

  /**
   * Fetches table list from the database
   */
  async getTables() {
    this.log('Fetching tables...');
    const { data, error } = await this.supabase.rpc('get_tables');
    
    if (error) throw new Error(`Failed to fetch tables: ${error.message}`);
    if (!data || data.length === 0) {
      throw new Error('No tables found in the database');
    }

    // Filter tables if specific ones were requested
    if (this.config.tables) {
      const tableSet = new Set(this.config.tables);
      return data.filter(table => tableSet.has(table.table_name));
    }

    return data;
  }

  /**
   * Fetches table definition including columns and constraints
   */
  async getTableDefinition(tableName) {
    this.log(`Fetching definition for table: ${tableName}`);
    const { data, error } = await this.supabase.rpc('get_table_info', {
      table_name_param: tableName
    });
    
    if (error) throw new Error(`Failed to fetch table definition: ${error.message}`);
    if (!data) throw new Error(`Could not find table information for ${tableName}`);

    // Get indexes
    const { data: indexes, error: idxError } = await this.supabase
      .from('get_table_indexes')
      .select('index_name, index_definition, is_primary, is_unique')
      .eq('table_name', tableName);
    
    if (idxError) throw new Error(`Failed to fetch indexes: ${idxError.message}`);

    return {
      ...data,
      indexes: indexes || []
    };
  }

  /**
   * Fetches database functions
   */
  async getFunctions() {
    this.log('Fetching functions...');
    const { data, error } = await this.supabase.rpc('get_db_functions');
    
    if (error) throw new Error(`Failed to fetch functions: ${error.message}`);
    return data || [];
  }

  /**
   * Fetches database triggers
   */
  async getTriggers() {
    this.log('Fetching triggers...');
    const { data, error } = await this.supabase.rpc('get_db_triggers');
    
    if (error) throw new Error(`Failed to fetch triggers: ${error.message}`);
    return data || [];
  }

  /**
   * Exports table data
   */
  async exportTableData(tableName) {
    if (this.config.schemaOnly) {
      return `-- Skipping data export for ${tableName} (schema-only mode)`;
    }

    this.log(`Exporting data from table: ${tableName}`);
    const { data, error } = await this.supabase
      .from(tableName)
      .select('*');
    
    if (error) throw new Error(`Failed to fetch data from ${tableName}: ${error.message}`);
    
    if (!data || data.length === 0) {
      return `-- No data found in table ${tableName}`;
    }

    return formatInsert(tableName, data);
  }

  /**
   * Exports database schema to Dart models
   * @param {Object} options - Options for Dart export
   * @param {string} options.outputDir - Directory to output Dart models
   * @param {boolean} options.generateDocs - Whether to generate documentation
   * @param {boolean} options.generateEquality - Whether to generate equality methods
   * @param {string} options.connectionString - PostgreSQL connection string
   * @returns {Promise<Object>} Result of the export operation
   */
  async exportToDart(options = {}) {
    try {
      const dartOptions = {
        outputDir: path.join(this.config.outputDir, 'dart_models'),
        generateDocs: true,
        generateEquality: true,
        connectionString: process.env.DATABASE_URL,
        ...options
      };

      this.log(`Exporting database schema to Dart models in ${dartOptions.outputDir}...`);
      
      const result = await convertDbToDart(dartOptions);
      
      this.log(`Successfully exported ${result.modelCount} Dart models`);
      return {
        success: true,
        modelCount: result.modelCount,
        outputDir: dartOptions.outputDir
      };
    } catch (error) {
      throw new Error(`Dart export failed: ${error.message}`);
    }
  }

  /**
   * Main export method
   */
  async export() {
    try {
      // 1. Create output directory
      await writeToFile(path.join(this.config.outputDir, '.gitkeep'), '');

      // 2. Export custom types
      const types = await this.getCustomTypes();
      if (types.length > 0) {
        await writeToFile(
          path.join(this.config.outputDir, '01_types.sql'),
          types.map(t => t.definition).join('\n\n'),
          this.config.verbose
        );
      }

      // 3. Export table schemas
      const tables = await this.getTables();
      let tableSchemas = '';
      for (const table of tables) {
        const definition = await this.getTableDefinition(table.table_name);
        tableSchemas += formatCreateTable(
          table.table_name,
          definition.columns,
          definition.constraints
        ) + '\n\n';
      }
      await writeToFile(
        path.join(this.config.outputDir, '02_tables.sql'),
        tableSchemas,
        this.config.verbose
      );

      // 4. Export table data
      if (!this.config.schemaOnly) {
        for (const table of tables) {
          const tableData = await this.exportTableData(table.table_name);
          await writeToFile(
            path.join(this.config.outputDir, `03_data_${table.table_name}.sql`),
            tableData,
            this.config.verbose
          );
        }
      }

      // 5. Export functions
      const functions = await this.getFunctions();
      if (functions.length > 0) {
        const functionDefs = functions.map(func => 
          `-- Function: ${func.routine_name}\n${func.routine_definition}`
        ).join('\n\n');
        await writeToFile(
          path.join(this.config.outputDir, '04_functions.sql'),
          functionDefs,
          this.config.verbose
        );
      }

      // 6. Export triggers
      const triggers = await this.getTriggers();
      if (triggers.length > 0) {
        const triggerDefs = triggers.map(trigger =>
          `-- Trigger: ${trigger.trigger_name} on ${trigger.event_object_table}\n${trigger.trigger_definition}`
        ).join('\n\n');
        await writeToFile(
          path.join(this.config.outputDir, '05_triggers.sql'),
          triggerDefs,
          this.config.verbose
        );
      }

      // 7. Generate master file
      const masterContent = this.generateMasterFile(tables);
      await writeToFile(
        path.join(this.config.outputDir, 'master.sql'),
        masterContent,
        this.config.verbose
      );

      return {
        success: true,
        stats: {
          types: types.length,
          tables: tables.length,
          functions: functions.length,
          triggers: triggers.length
        }
      };
    } catch (error) {
      throw new Error(`Export failed: ${error.message}`);
    }
  }

  /**
   * Generates the master file content
   */
  generateMasterFile(tables) {
    return `-- Master file to recreate database
-- Generated at: ${new Date().toISOString()}
-- Tables: ${tables.length}

-- Custom types
\\i 01_types.sql

-- Tables (in order)
\\i 02_tables.sql

-- Table data
${tables.map(t => `\\i 03_data_${t.table_name}.sql`).join('\n')}

-- Functions and triggers
\\i 04_functions.sql
\\i 05_triggers.sql
`;
  }
}