# Changelog

All notable changes to this project will be documented in this file.

## [1.0.6] - 2024-03-19

### Added
- Full support for freezed models generation
- Automatic handling of required fields with @Default annotations
- Proper handling of nullable fields in freezed models
- Enhanced enum generation with JsonValue support
- Improved type conversion for PostgreSQL to Dart types
- Better handling of default values in freezed models

### Changed
- Updated model generation to use freezed instead of json_serializable
- Improved documentation generation for freezed models
- Enhanced handling of foreign key references in model documentation
- Better type safety with proper nullability handling

### Fixed
- Issues with non-nullable fields requiring @Default or required annotation
- Enum value handling in freezed models
- Default value conversion for various PostgreSQL types
- Documentation formatting in generated models

## [1.0.5] - 2024-03-03

### Fixed
- Added missing exports for database objects:
  - Custom types (enums) now export to `01_types.sql`
  - Functions now export to `03_functions.sql`
  - Triggers now export to `04_triggers.sql`
- Automatic installation of helper functions before export
- Improved error handling for database object exports

## [1.0.4] - 2025-03-03

### Changed
- Updated default export paths for better project organization
  - SQL schema now exports to `./exported_database` by default
  - Dart models now export to `./lib/models` by default
- Improved constraint handling in both SQL and Dart exports
- Enhanced documentation of constraints in generated Dart models
- Streamlined export process to generate both SQL and Dart files in a single run

### Fixed
- Template literal interpolation in Dart model documentation
- Proper handling of USER-DEFINED types in schema export

## [1.0.3] - 2025-03-01

### Added
- Enhanced function export functionality with improved error handling
- Support for database views as Dart models
- Improved view handling with proper type mapping
- Better documentation generation for view models

## [1.0.2] - 2025-03-01

### Fixed
- Corrected GitHub repository URL format in package.json

## [1.0.1] - 2025-03-01

### Changed
- Updated GitHub repository URL to https://github.com/Albaraazain/supabase-dart-exporter

## [1.0.0] - 2025-03-01

### Added
- Initial release of supabase-dart-exporter
- Dart model generation from Supabase database schema for Flutter applications
- SQL export functionality for Supabase database schema and data
- Command-line interface with various options
- Support for both local and remote Supabase instances
- Documentation and examples 