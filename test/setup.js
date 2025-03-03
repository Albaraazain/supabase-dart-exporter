import { createClient } from '@supabase/supabase-js';
import { readFromFile } from '../lib/utils/files.js';
import path from 'path';
import { fileURLToPath } from 'url';
import { dirname } from 'path';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

async function installFunctions() {
  console.log('🔧 Installing test functions...');
  
  const supabase = createClient(
    process.env.SUPABASE_URL,
    process.env.SUPABASE_SERVICE_KEY
  );
  
  try {
    // Read and execute installation script
    const scriptPath = path.join(__dirname, '..', 'sql', 'install_functions.sql');
    const installScript = await readFromFile(scriptPath);
    
    // Split the script into individual statements
    const statements = installScript.split(';').filter(stmt => stmt.trim());
    
    // Execute each statement
    for (const stmt of statements) {
      const { error } = await supabase.rpc('exec_sql', {
        sql: stmt
      });
      
      if (error) {
        if (!error.message.includes('function exec_sql')) {
          throw error;
        }
        // If exec_sql doesn't exist yet, use raw SQL (only works in development)
        const { error: rawError } = await supabase
          .from('_sql')
          .insert({ query: stmt });
          
        if (rawError) {
          throw rawError;
        }
      }
    }
    
    console.log('✅ Test functions installed successfully');
  } catch (error) {
    console.error('❌ Failed to install test functions:', error.message);
    throw error;
  }
}

// Run setup if called directly
if (process.argv[1] === fileURLToPath(import.meta.url)) {
  installFunctions().catch(error => {
    console.error('Setup failed:', error);
    process.exit(1);
  });
}

export { installFunctions };