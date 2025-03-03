-- Custom types

CREATE TYPE check_status AS ENUM (
  'pending',
  'completed',
  'failed'
);

CREATE TYPE job_stage AS ENUM (
  'En Route',
  'At Location',
  'Diagnosing',
  'Quote Pending',
  'Quote Accepted',
  'In Progress',
  'Completed',
  'Cancelled'
);

CREATE TYPE photo_type AS ENUM (
  'before',
  'after',
  'issue',
  'other'
);

CREATE TYPE verification_method AS ENUM (
  'gps',
  'manual',
  'qr_code'
);

