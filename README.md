# Supabase Dart Exporter

A powerful CLI tool for exporting Supabase database schema to Dart models for Flutter applications.

## Features

- Export Supabase database schema to SQL files
- Generate Dart models from database schema with freezed support
- Support for all PostgreSQL constraints and types
- Automatic documentation generation
- Support for both local and remote Supabase instances
- Full freezed integration with immutable models
- Proper handling of default values and required fields
- Enhanced enum support with JsonValue annotations

## Installation

### Global Installation (Recommended)
```bash
npm install -g supabase-dart-exporter
```

### Project Installation
```bash
npm install --save-dev supabase-dart-exporter
```

### Flutter Project Setup

Add these dependencies to your `pubspec.yaml`:

```yaml
dependencies:
  freezed_annotation: ^2.4.1
  json_annotation: ^4.9.0

dev_dependencies:
  build_runner: ^2.4.15
  freezed: ^2.4.7
  json_serializable: ^6.7.1
```

## Configuration

Create a `.env` file in your project root:

```env
# For Supabase API access
SUPABASE_URL=http://localhost:54321        # Your Supabase project URL
SUPABASE_SERVICE_KEY=your-service-key      # Your service role key

# For PostgreSQL direct connection (required for Dart export)
DATABASE_URL=postgresql://postgres:postgres@localhost:54322/postgres
```

## Usage

### Basic Usage

1. Export both SQL schema and Dart models (recommended):
```bash
supabase-dart-exporter
```
This will:
- Export SQL schema to `./exported_database/`
- Generate Dart models in `./lib/models/`

2. Export SQL schema only:
```bash
supabase-dart-exporter --output ./my-schema
```

3. Generate Dart models only:
```bash
supabase-dart-exporter --dart --dart-output ./my-models
```

### Advanced Options

```bash
Options:
  -o, --output <dir>           Output directory for SQL exports (default: "./exported_database")
  -e, --env <path>            Path to .env file (default: ".env")
  -v, --verbose               Enable verbose logging
  --url <url>                 Supabase project URL (overrides .env)
  --key <key>                 Supabase service role key (overrides .env)
  --schema-only              Export schema without data
  --tables <tables>          Comma-separated list of tables to export
  --install-functions        Install required database functions
  --dart                     Export database schema to Dart models
  --dart-output <dir>        Output directory for Dart models (default: "./lib/models")
  --dart-no-docs            Disable documentation generation for Dart models
  --dart-no-equality        Disable equality methods for Dart models
  --connection-string <str>  PostgreSQL connection string (overrides .env)
```

### Examples

1. Export specific tables:
```bash
supabase-dart-exporter --tables users,profiles,posts
```

2. Custom output directories:
```bash
supabase-dart-exporter --output ./db/schema --dart --dart-output ./src/models
```

3. Minimal Dart models:
```bash
supabase-dart-exporter --dart --dart-no-docs --dart-no-equality
```

4. Using with remote Supabase:
```bash
supabase-dart-exporter --url https://your-project.supabase.co --key your-service-key
```

## Generated Files

### SQL Schema Export
The tool generates SQL files in the output directory:
- `02_tables.sql`: Table definitions with all constraints

### Dart Models
For each table, a corresponding Dart model is generated with:
- Full freezed integration for immutable data classes
- Proper nullability based on constraints
- Smart handling of default values with @Default annotations
- Enhanced enum support with @JsonValue annotations
- Documentation of constraints and relationships
- JSON serialization/deserialization
- Automatic copyWith functionality
- Deep equality comparison
- toString implementation
- Pattern matching support

Example Dart model:
```dart
/// Users model representing the users table in the database
@freezed
class Users with _$Users {
  const factory Users({
    /// Primary key
    @JsonKey(name: 'user_id')
    required String userId,

    /// Foreign key reference to profiles(id)
    @JsonKey(name: 'profile_id')
    String? profileId,

    /// Default: now()
    @JsonKey(name: 'created_at')
    @Default(DateTime.now()) DateTime createdAt,

    /// User status with predefined values
    @JsonKey(name: 'status')
    UserStatusType status,
  }) = _Users;

  factory Users.fromJson(Map<String, dynamic> json) => 
    _$UsersFromJson(json);
}

enum UserStatusType {
  @JsonValue('active')
  active,
  @JsonValue('inactive')
  inactive,
}
```

### After Generation

After generating the models, run:
```bash
dart run build_runner build --delete-conflicting-outputs
```

This will generate the necessary freezed and JSON serialization code.

## Best Practices

1. Always use version control and commit generated files
2. Review generated models before using in production
3. Keep your database schema clean and well-documented
4. Use meaningful constraint names in your database
5. Run the exporter whenever your schema changes
6. Run build_runner after generating new models
7. Take advantage of freezed's pattern matching features
8. Use the generated copyWith methods for immutable updates

## Troubleshooting

### Common Issues

1. **Connection Failed**
   - Verify your Supabase URL and service key
   - Check if your database is running
   - Ensure your firewall allows the connection

2. **Permission Denied**
   - Verify your service role key has sufficient permissions
   - Check database user permissions

3. **Type Mapping Issues**
   - Ensure custom types are properly defined
   - Check for unsupported PostgreSQL types

### Getting Help

- Open an issue on GitHub
- Check existing issues for solutions
- Include verbose logs with your reports: `--verbose`

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting PRs.

## License

MIT License - see LICENSE file for details 