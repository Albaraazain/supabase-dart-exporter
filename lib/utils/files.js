import fs from 'fs/promises';
import path from 'path';
import chalk from 'chalk';

/**
 * Ensures a directory exists, creating it if necessary
 * @param {string} dirPath - Path to the directory
 * @throws {Error} If directory creation fails
 */
export async function ensureDirectory(dirPath) {
  try {
    await fs.mkdir(dirPath, { recursive: true });
  } catch (error) {
    throw new Error(`Failed to create directory ${dirPath}: ${error.message}`);
  }
}

/**
 * Writes content to a file, creating directories if needed
 * @param {string} filePath - Path to the file
 * @param {string} content - Content to write
 * @param {boolean} verbose - Whether to log verbose output
 * @throws {Error} If file writing fails
 */
export async function writeToFile(filePath, content, verbose = false) {
  try {
    await ensureDirectory(path.dirname(filePath));
    await fs.writeFile(filePath, content, 'utf8');
    if (verbose) {
      console.log(chalk.green(`✓ Written to ${filePath}`));
    }
  } catch (error) {
    throw new Error(`Failed to write to ${filePath}: ${error.message}`);
  }
}

/**
 * Reads content from a file
 * @param {string} filePath - Path to the file
 * @returns {Promise<string>} File contents
 * @throws {Error} If file reading fails
 */
export async function readFromFile(filePath) {
  try {
    return await fs.readFile(filePath, 'utf8');
  } catch (error) {
    throw new Error(`Failed to read from ${filePath}: ${error.message}`);
  }
}

/**
 * Copies a file from source to destination
 * @param {string} sourcePath - Source file path
 * @param {string} destPath - Destination file path
 * @param {boolean} verbose - Whether to log verbose output
 * @throws {Error} If file copying fails
 */
export async function copyFile(sourcePath, destPath, verbose = false) {
  try {
    await ensureDirectory(path.dirname(destPath));
    await fs.copyFile(sourcePath, destPath);
    if (verbose) {
      console.log(chalk.green(`✓ Copied ${sourcePath} to ${destPath}`));
    }
  } catch (error) {
    throw new Error(`Failed to copy ${sourcePath} to ${destPath}: ${error.message}`);
  }
}

/**
 * Lists files in a directory
 * @param {string} dirPath - Path to the directory
 * @param {string} [extension] - Optional file extension filter
 * @returns {Promise<string[]>} Array of file paths
 * @throws {Error} If directory reading fails
 */
export async function listFiles(dirPath, extension) {
  try {
    const files = await fs.readdir(dirPath);
    if (extension) {
      return files.filter(file => file.endsWith(extension));
    }
    return files;
  } catch (error) {
    throw new Error(`Failed to list files in ${dirPath}: ${error.message}`);
  }
}

/**
 * Checks if a file exists
 * @param {string} filePath - Path to the file
 * @returns {Promise<boolean>} Whether the file exists
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
 * Creates a backup of a file with timestamp
 * @param {string} filePath - Path to the file
 * @param {boolean} verbose - Whether to log verbose output
 * @returns {Promise<string>} Path to the backup file
 * @throws {Error} If backup creation fails
 */
export async function createBackup(filePath, verbose = false) {
  try {
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupPath = `${filePath}.${timestamp}.bak`;
    await copyFile(filePath, backupPath, verbose);
    return backupPath;
  } catch (error) {
    throw new Error(`Failed to create backup of ${filePath}: ${error.message}`);
  }
}