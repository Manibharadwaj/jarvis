#!/usr/bin/env node
// Run: node db/run_migration.js "postgresql://postgres:password@db.xxxxx.supabase.co:5432/postgres"
// Get connection string from: Supabase > Project Settings > Database > Connection string (PSQL)

const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const connStr = process.argv[2];
if (!connStr || connStr === '--help') {
  console.log('');
  console.log('  Usage: node db/run_migration.js "<connection_string>"');
  console.log('');
  console.log('  Get connection string from:');
  console.log('  Supabase Dashboard → Project Settings → Database → Connection string');
  console.log('  Use the "PSQL" variant with your password.');
  console.log('');
  process.exit(1);
}

async function main() {
  const client = new Client({ connectionString: connStr });

  try {
    await client.connect();
    console.log('Connected to database.\n');

    const migrationsDir = path.join(__dirname);
    const files = fs.readdirSync(migrationsDir)
      .filter(f => f.endsWith('.sql'))
      .sort();

    if (files.length === 0) {
      console.log('No SQL migration files found in db/');
      process.exit(0);
    }

    for (const file of files) {
      console.log(`Running: ${file} ...`);
      const sql = fs.readFileSync(path.join(migrationsDir, file), 'utf8');
      await client.query(sql);
      console.log(`  ✓ ${file} done\n`);
    }

    console.log('All migrations completed successfully.');
  } catch (err) {
    console.error('Migration failed:', err.message);
    process.exit(1);
  } finally {
    await client.end();
  }
}

main();
