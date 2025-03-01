/**
 * SQL utility functions for database export operations
 */

/**
 * Escapes a string value for SQL
 * @param {any} value - Value to escape
 * @returns {string} Escaped value
 */
export function escapeSqlValue(value) {
  if (value === null) return 'NULL';
  if (typeof value === 'number') return value.toString();
  if (typeof value === 'boolean') return value ? 'TRUE' : 'FALSE';
  if (Array.isArray(value)) return `ARRAY[${value.map(escapeSqlValue).join(', ')}]`;
  if (typeof value === 'object') {
    return `'${JSON.stringify(value).replace(/'/g, "''")}'`;
  }
  return `'${value.toString().replace(/'/g, "''")}'`;
}

/**
 * Formats CREATE TABLE statement
 * @param {string} tableName - Name of the table
 * @param {Array<Object>} columns - Column definitions
 * @param {Array<Object>} constraints - Table constraints
 * @returns {string} Formatted CREATE TABLE statement
 */
export function formatCreateTable(tableName, columns, constraints = []) {
  const columnDefs = columns.map(col => {
    let def = `  ${col.column_name} ${col.data_type}`;
    if (col.character_maximum_length) {
      def = def.replace(col.data_type, `${col.data_type}(${col.character_maximum_length})`);
    }
    if (col.is_nullable === 'NO') def += ' NOT NULL';
    if (col.column_default) def += ` DEFAULT ${col.column_default}`;
    return def;
  });

  const constraintDefs = constraints.map(constraint => {
    switch (constraint.type) {
      case 'PRIMARY KEY':
        return `  CONSTRAINT ${constraint.name} PRIMARY KEY (${constraint.columns.join(', ')})`;
      case 'FOREIGN KEY':
        return `  CONSTRAINT ${constraint.name} ${constraint.foreign_key_info.definition}`;
      case 'CHECK':
        return `  CONSTRAINT ${constraint.name} CHECK ${constraint.check_clause}`;
      case 'UNIQUE':
        return `  CONSTRAINT ${constraint.name} UNIQUE (${constraint.columns.join(', ')})`;
      default:
        return '';
    }
  }).filter(Boolean);

  return [
    `CREATE TABLE IF NOT EXISTS ${tableName} (`,
    [...columnDefs, ...constraintDefs].join(',\n'),
    ');'
  ].join('\n');
}

/**
 * Formats INSERT statement for table data
 * @param {string} tableName - Name of the table
 * @param {Array<Object>} rows - Array of row data
 * @returns {string} Formatted INSERT statement
 */
export function formatInsert(tableName, rows) {
  if (!rows || rows.length === 0) {
    return `-- No data to insert for table ${tableName}`;
  }

  const columns = Object.keys(rows[0]);
  const values = rows.map(row => {
    const rowValues = columns.map(col => escapeSqlValue(row[col]));
    return `(${rowValues.join(', ')})`;
  });

  return [
    `INSERT INTO ${tableName} (${columns.join(', ')}) VALUES`,
    values.join(',\n'),
    ';'
  ].join('\n');
}

/**
 * Formats CREATE TYPE statement for enum
 * @param {string} typeName - Name of the enum type
 * @param {Array<string>} values - Enum values
 * @returns {string} Formatted CREATE TYPE statement
 */
export function formatCreateEnum(typeName, values) {
  const escapedValues = values.map(v => `'${v.replace(/'/g, "''")}'`);
  return `CREATE TYPE ${typeName} AS ENUM (${escapedValues.join(', ')});`;
}

/**
 * Formats CREATE INDEX statement
 * @param {string} tableName - Name of the table
 * @param {string} indexName - Name of the index
 * @param {Array<string>} columns - Columns to index
 * @param {Object} options - Index options
 * @returns {string} Formatted CREATE INDEX statement
 */
export function formatCreateIndex(tableName, indexName, columns, options = {}) {
  let sql = 'CREATE';
  if (options.unique) sql += ' UNIQUE';
  sql += ` INDEX IF NOT EXISTS ${indexName} ON ${tableName}`;
  if (options.method) sql += ` USING ${options.method}`;
  sql += ` (${columns.join(', ')})`;
  if (options.where) sql += ` WHERE ${options.where}`;
  return `${sql};`;
}

/**
 * Formats CREATE FUNCTION statement
 * @param {Object} functionDef - Function definition
 * @returns {string} Formatted CREATE FUNCTION statement
 */
export function formatCreateFunction(functionDef) {
  return [
    `CREATE OR REPLACE FUNCTION ${functionDef.name}(${functionDef.parameters})`,
    `RETURNS ${functionDef.returns}`,
    'AS $$',
    functionDef.body,
    '$$',
    `LANGUAGE ${functionDef.language};`
  ].join('\n');
}

/**
 * Formats CREATE TRIGGER statement
 * @param {Object} triggerDef - Trigger definition
 * @returns {string} Formatted CREATE TRIGGER statement
 */
export function formatCreateTrigger(triggerDef) {
  return [
    `CREATE TRIGGER ${triggerDef.name}`,
    `${triggerDef.timing} ${triggerDef.event}`,
    `ON ${triggerDef.table}`,
    `FOR EACH ${triggerDef.for_each}`,
    `EXECUTE FUNCTION ${triggerDef.function}();`
  ].join('\n');
}