import fs from 'fs-extra';
import path from 'path';
import { camelCase, pascalCase } from 'change-case';

/**
 * Read content from a file
 */
export async function readFromFile(filePath) {
  try {
    return await fs.readFile(filePath, 'utf8');
  } catch (error) {
    throw new Error(`Failed to read file ${filePath}: ${error.message}`);
  }
}

/**
 * Write content to a file, creating directories if needed
 */
export async function writeToFile(filePath, content) {
  try {
    await fs.ensureDir(path.dirname(filePath));
    await fs.writeFile(filePath, content, 'utf8');
  } catch (error) {
    throw new Error(`Failed to write file ${filePath}: ${error.message}`);
  }
}

/**
 * Check if a file exists
 */
export async function fileExists(filePath) {
  try {
    await fs.access(filePath);
    return true;
  } catch {
    return false;
  }
}

/**
 * Generate table creation SQL with constraints
 */
export function generateTableSQL(tableName, columns, constraints) {
  let sql = `CREATE TABLE IF NOT EXISTS ${tableName} (\n`;
  
  // Add columns
  const columnLines = columns.map(col => {
    let line = `  ${col.column_name} ${col.data_type}`;
    
    // Add length for character types
    if (col.character_maximum_length) {
      line += `(${col.character_maximum_length})`;
    }
    
    // Add numeric precision and scale
    if (col.numeric_precision && col.data_type !== 'serial') {
      if (col.numeric_scale) {
        line += `(${col.numeric_precision},${col.numeric_scale})`;
      } else {
        line += `(${col.numeric_precision})`;
      }
    }
    
    // Add nullability
    line += col.is_nullable === 'NO' ? ' NOT NULL' : '';
    
    // Add default value
    if (col.column_default) {
      line += ` DEFAULT ${col.column_default}`;
    }
    
    return line;
  });
  
  // Add constraints
  if (constraints && constraints.length > 0) {
    constraints.forEach(constraint => {
      let constraintLine = '';
      
      switch (constraint.constraint_type) {
        case 'PRIMARY KEY':
          constraintLine = `  CONSTRAINT ${constraint.constraint_name} PRIMARY KEY (${constraint.column_name})`;
          break;
          
        case 'FOREIGN KEY':
          constraintLine = `  CONSTRAINT ${constraint.constraint_name} FOREIGN KEY (${constraint.column_name}) ` +
            `REFERENCES ${constraint.foreign_table_name}(${constraint.foreign_column_name})`;
          
          // Add ON UPDATE action
          if (constraint.confupdtype && constraint.confupdtype !== 'a') {
            constraintLine += ` ON UPDATE ${getActionType(constraint.confupdtype)}`;
          }
          
          // Add ON DELETE action
          if (constraint.confdeltype && constraint.confdeltype !== 'a') {
            constraintLine += ` ON DELETE ${getActionType(constraint.confdeltype)}`;
          }
          break;
          
        case 'UNIQUE':
          constraintLine = `  CONSTRAINT ${constraint.constraint_name} UNIQUE (${constraint.column_name})`;
          break;
          
        case 'CHECK':
          if (constraint.check_clause) {
            constraintLine = `  CONSTRAINT ${constraint.constraint_name} CHECK (${constraint.check_clause})`;
          }
          break;
      }
      
      if (constraintLine) {
        columnLines.push(constraintLine);
      }
    });
  }
  
  sql += columnLines.join(',\n');
  sql += '\n);\n';
  
  return sql;
}

/**
 * Convert PostgreSQL referential action type to SQL keyword
 */
function getActionType(type) {
  switch (type) {
    case 'c': return 'CASCADE';
    case 'n': return 'SET NULL';
    case 'd': return 'SET DEFAULT';
    case 'r': return 'RESTRICT';
    default: return 'NO ACTION';
  }
}

/**
 * Generate Dart model code
 */
export function generateDartModel(tableName, columns, constraints, options = {}) {
  const className = pascalCase(tableName);
  const { generateDocs = true } = options;

  // Get primary key columns
  const primaryKeys = constraints.filter(c => c.constraint_type === 'PRIMARY KEY')
    .map(c => c.column_name)
    .filter(Boolean);

  // Get foreign key constraints
  const foreignKeys = constraints.filter(c => c.constraint_type === 'FOREIGN KEY' && c.column_name)
    .map(c => ({
      column: c.column_name,
      foreignTable: c.foreign_table_name,
      foreignColumn: c.foreign_column_name
    }));

  // Get enum constraints
  const enumConstraints = constraints.filter(c => 
    c.constraint_type === 'CHECK' && 
    c.check_clause?.includes('= ANY (ARRAY[')
  ).map(c => {
    const match = c.check_clause.match(/\(\((.*?) = ANY \(ARRAY\[(.*?)\]\)\)/);
    if (match) {
      const columnName = match[1];
      const values = match[2].split(',').map(v => 
        v.trim().replace(/^'|'::text'$/g, '').replace(/::[a-z]+$/, '').replace(/'/g, '')
      );
      return {
        column: columnName,
        values
      };
    }
    return null;
  }).filter(Boolean);

  let code = `// GENERATED CODE - DO NOT MODIFY BY HAND

// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

import 'package:freezed_annotation/freezed_annotation.dart';

part '${tableName}.g.dart';
part '${tableName}.freezed.dart';

`;

  // Generate enum types for constrained fields outside the class
  enumConstraints.forEach(constraint => {
    const enumName = pascalCase(constraint.column) + 'Type';
    code += `enum ${enumName} {
${constraint.values.map(v => `  @JsonValue('${v}')
  ${camelCase(v)}`).join(',\n')},
}

`;
  });

  code += `/// Model representing the ${tableName} table in the database.
/// This model was auto-generated from the database schema.
@freezed
class ${className} with _$${className} {
  const factory ${className}({
`;

  // Generate fields
  columns.forEach(column => {
    if (generateDocs) {
      code += '\n';
      code += `    /// ${column.column_name} field\n`;
      if (primaryKeys.includes(column.column_name)) {
        code += '    /// Primary key\n';
      }
      const fk = foreignKeys.find(fk => fk.column === column.column_name);
      if (fk) {
        code += `    /// Foreign key reference to ${fk.foreignTable}(${fk.foreignColumn})\n`;
      }
      if (column.column_default) {
        code += `    /// Default: ${column.column_default}\n`;
      }
    }

    // Convert PostgreSQL types to Dart types
    let dartType = getDartType(column.data_type, column.is_nullable === 'YES');

    // Check if field has an enum constraint
    const enumConstraint = enumConstraints.find(c => c.column === column.column_name);
    if (enumConstraint) {
      dartType = pascalCase(column.column_name) + 'Type';
      if (column.is_nullable === 'YES') {
        dartType += '?';
      }
    }

    const fieldName = camelCase(column.column_name);
    code += `    @JsonKey(name: '${column.column_name}')\n`;

    // Handle required fields and default values
    if (column.is_nullable === 'NO') {
      if (column.column_default) {
        // For non-null fields with default values, use @Default annotation
        const defaultValue = getDefaultValue(column.column_default, column.data_type);
        if (defaultValue !== null) {
          code += `    @Default(${defaultValue}) ${dartType} ${fieldName},\n`;
        } else {
          code += `    required ${dartType} ${fieldName},\n`;
        }
      } else {
        code += `    required ${dartType} ${fieldName},\n`;
      }
    } else {
      code += `    ${dartType} ${fieldName},\n`;
    }
  });

  code += `  }) = _${className};\n\n`;
  code += `  factory ${className}.fromJson(Map<String, dynamic> json) => _$${className}FromJson(json);\n`;
  code += '}\n';

  return code;
}

function getDefaultValue(defaultValue, dataType) {
  if (!defaultValue) return null;

  // Handle nextval sequences
  if (defaultValue.includes('nextval(')) {
    return null;
  }

  // Handle now() defaults
  if (defaultValue.includes('now()')) {
    return 'DateTime.now()';
  }

  // Handle text defaults
  if (dataType === 'text' || dataType === 'character varying') {
    const match = defaultValue.match(/'([^']*)'::text/);
    if (match) {
      return `'${match[1]}'`;
    }
  }

  // Handle numeric defaults
  if (dataType === 'integer' || dataType === 'bigint' || dataType === 'numeric') {
    const numValue = parseInt(defaultValue, 10);
    if (!isNaN(numValue)) {
      return numValue.toString();
    }
  }

  // Handle boolean defaults
  if (dataType === 'boolean') {
    if (defaultValue.toLowerCase() === 'true') return 'true';
    if (defaultValue.toLowerCase() === 'false') return 'false';
  }

  return null;
}

/**
 * Convert PostgreSQL type to Dart type
 */
export function getDartType(pgType, isNullable = false) {
  const nullSuffix = isNullable ? '?' : '';
  
  switch (pgType.toLowerCase()) {
    case 'integer':
    case 'smallint':
    case 'bigint':
    case 'serial':
    case 'bigserial':
      return `int${nullSuffix}`;
      
    case 'decimal':
    case 'numeric':
    case 'real':
    case 'double precision':
    case 'float':
    case 'float4':
    case 'float8':
      return `double${nullSuffix}`;
      
    case 'boolean':
      return `bool${nullSuffix}`;
      
    case 'timestamp':
    case 'timestamp with time zone':
    case 'timestamp without time zone':
    case 'timestamptz':
    case 'date':
    case 'time':
    case 'time with time zone':
    case 'time without time zone':
    case 'timetz':
      return `DateTime${nullSuffix}`;
      
    case 'json':
    case 'jsonb':
      return `Map<String, dynamic>${nullSuffix}`;
      
    case 'uuid':
      return `String${nullSuffix}`;

    case 'bytea':
      return `List<int>${nullSuffix}`;

    case 'text[]':
    case 'varchar[]':
    case 'character varying[]':
      return `List<String>${nullSuffix}`;

    case 'integer[]':
    case 'int[]':
    case 'bigint[]':
      return `List<int>${nullSuffix}`;

    case 'boolean[]':
      return `List<bool>${nullSuffix}`;

    case 'numeric[]':
    case 'decimal[]':
    case 'double precision[]':
      return `List<double>${nullSuffix}`;
      
    default:
      return `String${nullSuffix}`;
  }
} 