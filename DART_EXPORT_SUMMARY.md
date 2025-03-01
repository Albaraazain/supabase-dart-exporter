# Dart Export Functionality

We've successfully added Dart model generation capabilities to the `@voltzy/db-export` package. This feature allows users to automatically generate Dart models from their PostgreSQL database schema, making it easier to integrate Supabase with Flutter applications.

## Implementation Details

### 1. Core Functionality

The Dart export functionality is implemented in `lib/utils/dart.js`, which provides:

- PostgreSQL to Dart type mapping
- Table and column information retrieval
- Dart model class generation with:
  - Properties with appropriate types
  - Constructor with named parameters
  - `fromJson` factory method
  - `toJson` method
  - `copyWith` method for immutability
  - Optional documentation
  - Optional equality and hash code methods

### 2. Integration with Exporter

The main `DatabaseExporter` class in `lib/exporter.js` has been extended with an `exportToDart` method that:

- Takes configuration options for the Dart export
- Sets sensible defaults
- Handles errors gracefully
- Returns statistics about the export

### 3. CLI Integration

The command-line interface in `bin/db-export.js` has been updated with new options:

- `--dart`: Enable Dart export
- `--dart-output`: Specify output directory for Dart models
- `--dart-no-docs`: Disable documentation generation
- `--dart-no-equality`: Disable equality methods
- `--connection-string`: Specify PostgreSQL connection string

### 4. Documentation

- README.md has been updated with Dart export information
- New example script for Dart export usage
- Updated implementation summary
- Added DATABASE_URL to .env.example

## Usage Examples

### CLI Usage

```bash
# Basic Dart export
db-export --dart

# Customize output directory
db-export --dart --dart-output ./lib/models

# Disable documentation and equality methods
db-export --dart --dart-no-docs --dart-no-equality

# Export both SQL and Dart in one command
db-export --output ./my-database-export --dart
```

### Programmatic Usage

```javascript
import { DatabaseExporter } from '@voltzy/db-export';

const exporter = new DatabaseExporter({
  supabaseUrl: process.env.SUPABASE_URL,
  supabaseKey: process.env.SUPABASE_SERVICE_KEY,
  outputDir: './my-exports'
});

async function run() {
  try {
    // Export database to Dart models
    const result = await exporter.exportToDart({
      outputDir: './lib/models',
      generateDocs: true,
      generateEquality: true,
      connectionString: process.env.DATABASE_URL
    });
    
    console.log(`Generated ${result.modelCount} Dart models`);
  } catch (error) {
    console.error('Export failed:', error.message);
  }
}
```

## Generated Dart Models

The generated Dart models include:

1. Class definition with appropriate types
2. Documentation comments (if enabled)
3. Constructor with named parameters
4. Factory method for JSON deserialization
5. Method for JSON serialization
6. CopyWith method for creating modified instances
7. ToString method for debugging
8. Equality and hash code methods (if enabled)

Example of a generated model:

```dart
/// Represents a user in the system
class User {
  final int id;
  final String name;
  final String? email;
  final DateTime createdAt;

  User({
    required this.id,
    required this.name,
    this.email,
    required this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      name: json['name'],
      email: json['email'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'created_at': createdAt.toIso8601String(),
    };
  }

  User copyWith({
    int? id,
    String? name,
    String? email,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'User(id: $id, name: $name, email: $email, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is User &&
        other.id == id &&
        other.name == name &&
        other.email == email &&
        other.createdAt == createdAt;
  }

  @override
  int get hashCode {
    return Object.hash(id, name, email, createdAt);
  }
}
```

## Next Steps

1. Add tests for the Dart export functionality
2. Support for more complex PostgreSQL types
3. Add support for relationships between models
4. Add support for more programming languages (TypeScript, Kotlin, Swift) 