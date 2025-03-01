# supabase-dart-exporter

A powerful CLI tool for exporting Supabase database schemas to Dart models for Flutter applications, with additional SQL export capabilities.

## Features

- Export complete database schema (tables, types, functions, triggers)
- Export table data as SQL insert statements
- Generate Dart models from your database schema for Flutter applications
- Configurable output directories
- Verbose logging option
- Support for both local and remote Supabase instances

## Installation

```bash
npm install -g supabase-dart-exporter
```

## Configuration

Create a `.env` file in your project root with the following variables:

```
# For Supabase API access (optional if using DATABASE_URL)
SUPABASE_URL=http://localhost:54321
SUPABASE_SERVICE_KEY=your-service-key

# For direct PostgreSQL connection (required for Dart export)
DATABASE_URL=postgresql://postgres:postgres@127.0.0.1:54322/postgres
```

## Usage

### Basic Export

Export your database schema and data to SQL files:

```bash
supabase-dart-exporter
```

By default, this will create an `exported_database` directory with SQL files.

### Custom Output Directory

```bash
supabase-dart-exporter --output ./my-database-export
```

### Export to Dart Models

```bash
supabase-dart-exporter --dart
```

This will generate Dart model classes in `exported_database/dart_models`.

### Custom Dart Output Directory

```bash
supabase-dart-exporter --dart --dart-output ./my-dart-models
```

### Verbose Logging

```bash
supabase-dart-exporter --verbose
```

### Combining Options

```bash
supabase-dart-exporter --output ./my-database-export --dart --dart-output ./my-dart-models --verbose
```

## Dart Model Generation

The generated Dart models include:

- Class properties with appropriate types
- Default constructor
- Named constructor for JSON deserialization
- `toJson()` method for serialization
- `copyWith()` method for immutability
- `toString()` method
- Equality and hash code implementations

Example generated model:

```dart
import 'package:flutter/material.dart';
import 'dart:core';

/// Represents the users table in the database
/// Auto-generated from database schema
class Users {
  final String? user_id;
  final String? email;
  final String? full_name;
  // ... other fields

  Users({
    this.user_id,
    this.email,
    this.full_name,
    // ... other fields
  });

  factory Users.fromJson(Map<String, dynamic> json) {
    return Users(
      user_id: json['user_id'],
      email: json['email'],
      full_name: json['full_name'],
      // ... other fields
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': user_id,
      'email': email,
      'full_name': full_name,
      // ... other fields
    };
  }

  // ... other methods
}
```

## Requirements

- Node.js >= 18.0.0
- For Dart export: PostgreSQL connection

## License

MIT

## Author

Voltzy Professional 