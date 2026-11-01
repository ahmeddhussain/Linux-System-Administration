# The S3 bucket that stores Terraform state for every layer (D-016).
# It was created before this code existed, so it is adopted with import
# blocks; applying again is harmless. Never destroyed by any script.

import {
  to = aws_s3_bucket.state
  id = var.state_bucket_name
}

import {
  to = aws_s3_bucket_public_access_block.state
  id = var.state_bucket_name
}

import {
  to = aws_s3_bucket_server_side_encryption_configuration.state
  id = var.state_bucket_name
}

import {
  to = aws_s3_bucket_ownership_controls.state
  id = var.state_bucket_name
}

resource "aws_s3_bucket" "state" {
  bucket = var.state_bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

# Every apply writes a new state object; versioning keeps the previous ones
# so a corrupted or overwritten state can be restored.
resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Old versions are only needed for recovery; expire them to bound cost.
resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expire-old-state-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.state]
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 with a bucket key, as the bucket was created. A customer managed KMS
# key would add about $1/month and key policy work for no gain in this lab.
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

# ACLs disabled; the account owns every object.
resource "aws_s3_bucket_ownership_controls" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# State contains infrastructure details; refuse any request not made over TLS.
data "aws_iam_policy_document" "state_tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.state.arn,
      "${aws_s3_bucket.state.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}
