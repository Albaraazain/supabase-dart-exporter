/**
 * Database to Dart Model Converter
 * 
 * This module provides functionality to convert PostgreSQL database schema to Dart models.
 */

import fs from 'fs-extra';
import path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const execAsync = promisify(exec);

// PostgreSQL to Dart type mapping
const PG_TO_DART_TYPE = {
  // Text types
  'character varying': 'String',
  'varchar': 'String',
  'character': 'String',
  'char': 'String',
  'text': 'String',
  
  // Numeric types
  'smallint': 'int',
  'integer': 'int',
  'bigint': 'int',
  'decimal': 'double',
  'numeric': 'double',
  'real': 'double',
  'double precision': 'double',
  
  // Boolean type
  'boolean': 'bool',
  
  // Date/Time types
  'date': 'DateTime',
  'timestamp': 'DateTime',
  'timestamp without time zone': 'DateTime',
  'timestamp with time zone': 'DateTime',
  'time': 'TimeOfDay',
  'time without time zone': 'TimeOfDay',
  'time with time zone': 'TimeOfDay',
  
  // JSON types
  'json': 'Map<String, dynamic>',
  'jsonb': 'Map<String, dynamic>',
  
  // UUID type
  'uuid': 'String',
  
  // Array types are handled separately
};

/**
 * Convert snake_case to PascalCase
 * @param {string} str - String in snake_case
 * @returns {string} String in PascalCase
 */
function toPascalCase(str) {
  return str
    .split('_')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join('');
}

/**
 * Run a psql command and get the output
 * @param {string} command - SQL command to execute
 * @param {string} connectionString - PostgreSQL connection string
 * @returns {Promise<string[]>} Array of result lines
 */
async function runPsqlCommand(command, connectionString) {
  try {
    const { stdout, stderr } = await execAsync(`PAGER=cat psql ${connectionString} -t -A -c "${command}"`);
    if (stderr && !stderr.includes('NOTICE')) {
      console.error(`Error running psql command: ${stderr}`);
    }
    return stdout.trim().split('\n').filter(line => line.trim() !== '');
  } catch (error) {
    console.error(`Failed to execute psql command: ${error.message}`);
    throw error;
  }
}

/**
 * Get all tables in the public schema
 * @param {string} connectionString - PostgreSQL connection string
 * @returns {Promise<string[]>} Array of table names
 */
async function getTables(connectionString) {
  const query = `
    SELECT table_name 
    FROM information_schema.tables 
    WHERE table_schema = 'public' 
    AND table_type = 'BASE TABLE';
  `;
  return await runPsqlCommand(query, connectionString);
}

/**
 * Get detailed column information for a table
 * @param {string} tableName - Name of the table
 * @param {string} connectionString - PostgreSQL connection string
 * @returns {Promise<Object[]>} Array of column information objects
 */
async function getTableColumns(tableName, connectionString) {
  const query = `
    SELECT 
      column_name,
      data_type,
      udt_name,
      is_nullable,
      column_default,
      character_maximum_length,
      numeric_precision,
      numeric_scale
    FROM information_schema.columns 
    WHERE table_name = '${tableName}'
    AND table_schema = 'public'
    ORDER BY ordinal_position;
  `;
  
  const columnData = await runPsqlCommand(query, connectionString);
  
  return columnData.map(line => {
    const [
      columnName, 
      dataType, 
      udtName, 
      isNullable, 
      columnDefault, 
      charMaxLength, 
      numPrecision, 
      numScale
    ] = line.split('|');
    
    return {
      name: columnName,
      pgType: dataType,
      udtName: udtName,
      isNullable: isNullable === 'YES',
      default: columnDefault,
      charMaxLength: charMaxLength ? parseInt(charMaxLength) : null,
      numPrecision: numPrecision ? parseInt(numPrecision) : null,
      numScale: numScale ? parseInt(numScale) : null
    };
  });
}

/**
 * Determine Dart type from PostgreSQL type
 * @param {Object} column - Column information object
 * @returns {string} Dart type
 */
function getDartType(column) {
  // Handle array types
  if (column.pgType.startsWith('ARRAY')) {
    const baseType = column.pgType.match(/ARRAY\[(.*)\]/)[1];
    const dartBaseType = PG_TO_DART_TYPE[baseType] || 'dynamic';
    return `List<${dartBaseType}>`;
  }
  
  // Handle enum types
  if (column.pgType === 'USER-DEFINED') {
    // Custom handling for enums could go here, but for now treat as String
    return 'String';
  }
  
  // Use the mapping for standard types
  return PG_TO_DART_TYPE[column.pgType] || 'dynamic';
}

/**
 * Generate Dart model for a table
 * @param {string} tableName - Name of the table
 * @param {Object} options - Configuration options
 * @returns {Promise<string>} Dart class content
 */
async function generateDartModel(tableName, options) {
  try {
    console.log(`Generating Dart model for table: ${tableName}`);
    
    const columns = await getTableColumns(tableName, options.connectionString);
    const className = toPascalCase(tableName);
    
    let dartContent = '';
    
    // Add imports
    const needsMaterial = columns.some(col => 
      getDartType(col).includes('DateTime') || getDartType(col).includes('TimeOfDay')
    );
    
    if (needsMaterial) {
      dartContent += "import 'package:flutter/material.dart';\n";
    }
    
    // Add import for Object.hash if needed
    if (options.generateEquality) {
      dartContent += "import 'dart:core';\n";
      dartContent += "import 'package:collection/collection.dart';\n";
    }
    
    dartContent += "\n";
    
    // Add class documentation
    if (options.generateDocs) {
      dartContent += `/// ${className} model representing the ${tableName} table in the database\n`;
      dartContent += `/// This model was auto-generated from the database schema.\n`;
    }
    
    // Start class definition
    dartContent += `class ${className} {\n`;
    
    // Add properties
    columns.forEach(column => {
      const dartType = getDartType(column);
      const fieldType = column.isNullable ? `${dartType}?` : dartType;
      
      if (options.generateDocs) {
        dartContent += `  /// ${column.name} field\n`;
        if (column.default) {
          dartContent += `  /// Default: ${column.default}\n`;
        }
      }
      
      dartContent += `  final ${fieldType} ${column.name};\n\n`;
    });
    
    // Constructor
    dartContent += `  ${className}({\n`;
    columns.forEach(column => {
      const required = !column.isNullable ? 'required ' : '';
      dartContent += `    ${required}this.${column.name},\n`;
    });
    dartContent += `  });\n\n`;
    
    // fromJson factory
    dartContent += `  factory ${className}.fromJson(Map<String, dynamic> json) {\n`;
    dartContent += `    return ${className}(\n`;
    
    columns.forEach(column => {
      const dartType = getDartType(column);
      
      if (dartType === 'DateTime') {
        dartContent += `      ${column.name}: json['${column.name}'] != null ? (json['${column.name}'] is String ? DateTime.parse(json['${column.name}']) : DateTime.fromMillisecondsSinceEpoch(json['${column.name}'] * 1000)) : null,\n`;
      } 
      else if (dartType === 'TimeOfDay') {
        dartContent += `      ${column.name}: json['${column.name}'] != null ? _timeFromString(json['${column.name}']) : null,\n`;
      } 
      else if (dartType === 'int') {
        dartContent += `      ${column.name}: json['${column.name}'] != null ? (json['${column.name}'] is int ? json['${column.name}'] : (json['${column.name}'] is double ? (json['${column.name}'] as double).toInt() : int.tryParse(json['${column.name}'].toString()) ?? 0)) : null,\n`;
      } 
      else if (dartType === 'double') {
        dartContent += `      ${column.name}: json['${column.name}'] != null ? (json['${column.name}'] is double ? json['${column.name}'] : (json['${column.name}'] is int ? (json['${column.name}'] as int).toDouble() : double.tryParse(json['${column.name}'].toString()) ?? 0.0)) : null,\n`;
      }
      else if (dartType.startsWith('List<')) {
        dartContent += `      ${column.name}: json['${column.name}'] != null ? List<${dartType.match(/List<(.*)>/)[1]}>.from(json['${column.name}']) : null,\n`;
      }
      else if (dartType === 'Map<String, dynamic>') {
        dartContent += `      ${column.name}: json['${column.name}'] != null ? Map<String, dynamic>.from(json['${column.name}']) : null,\n`;
      }
      else {
        dartContent += `      ${column.name}: json['${column.name}'],\n`;
      }
    });
    
    dartContent += `    );\n`;
    dartContent += `  }\n\n`;
    
    // Helper method for TimeOfDay if needed
    if (needsMaterial && columns.some(col => getDartType(col) === 'TimeOfDay')) {
      dartContent += `  static TimeOfDay _timeFromString(String time) {\n`;
      dartContent += `    try {\n`;
      dartContent += `      final parts = time.split(':');\n`;
      dartContent += `      return TimeOfDay(\n`;
      dartContent += `        hour: int.parse(parts[0].trim()),\n`;
      dartContent += `        minute: parts.length > 1 ? int.parse(parts[1].trim()) : 0,\n`;
      dartContent += `      );\n`;
      dartContent += `    } catch (e) {\n`;
      dartContent += `      // Return default time if parsing fails\n`;
      dartContent += `      return const TimeOfDay(hour: 0, minute: 0);\n`;
      dartContent += `    }\n`;
      dartContent += `  }\n\n`;
    }
    
    // toJson method
    dartContent += `  Map<String, dynamic> toJson() {\n`;
    dartContent += `    final Map<String, dynamic> data = {};\n\n`;
    
    columns.forEach(column => {
      const dartType = getDartType(column);
      const nullCheck = column.isNullable ? `if (${column.name} != null) ` : '';
      
      if (dartType === 'DateTime') {
        dartContent += `    ${nullCheck}data['${column.name}'] = ${column.name}${column.isNullable ? '?' : ''}.toIso8601String();\n`;
      } 
      else if (dartType === 'TimeOfDay') {
        dartContent += `    ${nullCheck}data['${column.name}'] = '${column.isNullable ? '${' + column.name + '?.hour}:${' + column.name + '?.minute}' : '${' + column.name + '.hour}:${' + column.name + '.minute}'}';\n`;
      } 
      else {
        dartContent += `    ${nullCheck}data['${column.name}'] = ${column.name};\n`;
      }
    });
    
    dartContent += `    return data;\n`;
    dartContent += `  }\n\n`;
    
    // copyWith method
    dartContent += `  ${className} copyWith({\n`;
    columns.forEach(column => {
      const dartType = getDartType(column);
      const fieldType = column.isNullable ? dartType : dartType; // No need for ? since it's an optional parameter
      
      dartContent += `    ${fieldType}? ${column.name},\n`;
    });
    dartContent += `  }) {\n`;
    dartContent += `    return ${className}(\n`;
    columns.forEach(column => {
      dartContent += `      ${column.name}: ${column.name} ?? this.${column.name},\n`;
    });
    dartContent += `    );\n`;
    dartContent += `  }\n\n`;
    
    // toString method
    dartContent += `  @override\n`;
    dartContent += `  String toString() {\n`;
    dartContent += `    return '${className}(${columns.map(c => `${c.name}: \$${c.name}`).join(', ')})';\n`;
    dartContent += `  }\n`;
    
    // Equality and hashCode if enabled
    if (options.generateEquality) {
      // equals method
      dartContent += `\n  @override\n`;
      dartContent += `  bool operator ==(Object other) {\n`;
      dartContent += `    if (identical(this, other)) return true;\n`;
      dartContent += `    return other is ${className} &&\n`;
      
      const equalsLines = columns.map(c => `      other.${c.name} == ${c.name}`);
      dartContent += equalsLines.join(' &&\n') + ';\n';
      dartContent += `  }\n\n`;
      
      // hashCode method - limit to 20 fields max for Object.hash
      dartContent += `  @override\n`;
      if (columns.length <= 20) {
        dartContent += `  int get hashCode => Object.hash(\n`;
        dartContent += columns.map(c => `      ${c.name}`).join(',\n') + '\n';
        dartContent += `    );\n`;
      } else {
        // For models with more than 20 fields, use a different approach
        dartContent += `  int get hashCode {\n`;
        dartContent += `    return ${columns.map(c => `${c.name}.hashCode`).join(' ^ ')};\n`;
        dartContent += `  }\n`;
      }
    }
    
    // Close class
    dartContent += `}\n`;
    
    return dartContent;
  } catch (error) {
    console.error(`Error generating Dart model for ${tableName}: ${error.message}`);
    throw error;
  }
}

/**
 * Convert database schema to Dart models
 * @param {Object} options - Configuration options
 * @returns {Promise<Object>} Result statistics
 */
export async function convertDbToDart(options) {
  console.log('🔄 Starting PostgreSQL to Dart model conversion...');
  
  const defaultOptions = {
    outputDir: './dart_models',
    connectionString: 'postgresql://postgres:postgres@127.0.0.1:54322/postgres',
    generateDocs: true,
    formatDartFiles: true,
    generateEquality: true,
    verbose: false
  };
  
  // Merge options with defaults
  const config = { ...defaultOptions, ...options };
  
  // Create output directory if it doesn't exist
  if (!fs.existsSync(config.outputDir)) {
    fs.mkdirSync(config.outputDir, { recursive: true });
    console.log(`📁 Created output directory: ${config.outputDir}`);
  }
  
  try {
    // Get all tables
    const tables = await getTables(config.connectionString);
    console.log(`🔍 Found ${tables.length} tables to convert`);
    
    // Generate a model for each table
    let successCount = 0;
    let errorCount = 0;
    
    for (const table of tables) {
      try {
        // Generate Dart content
        const dartContent = await generateDartModel(table, config);
        
        // Write to file
        const dartFileName = `${table}.dart`;
        const dartPath = path.join(config.outputDir, dartFileName);
        fs.writeFileSync(dartPath, dartContent);
        
        // Format if enabled
        if (config.formatDartFiles) {
          try {
            await execAsync(`dart format "${dartPath}"`);
          } catch (e) {
            console.warn(`⚠️ Could not format ${dartFileName}. Is dart format installed?`);
          }
        }
        
        console.log(`✅ Converted: ${table} → ${dartFileName}`);
        successCount++;
      } catch (error) {
        console.error(`❌ Failed to convert ${table}: ${error.message}`);
        errorCount++;
      }
    }
    
    console.log(`\n🏁 Conversion complete:`);
    console.log(`   ✅ ${successCount} models successfully generated`);
    console.log(`   ❌ ${errorCount} models failed`);
    console.log(`   📁 Dart models written to: ${config.outputDir}`);
    
    return {
      success: successCount,
      failed: errorCount,
      outputDir: config.outputDir
    };
    
  } catch (error) {
    console.error(`❌ Error during conversion: ${error.message}`);
    throw error;
  }
} 