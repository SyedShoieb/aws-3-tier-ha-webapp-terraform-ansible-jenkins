# Identify the AWS account so the bucket name is globally unique.

# Dedicated S3 bucket for Ansible SSM file transfers.
resource "aws_s3_bucket" "ansible_ssm" {
  bucket = "${substr(replace(lower(var.project_name), "_", "-"), 0, 20)}-ansible-ssm-${data.aws_caller_identity.current.account_id}-${var.aws_region}"

  force_destroy = false

  tags = merge(local.common_tags, {
    Name    = "${var.project_name}-ansible-ssm"
    Purpose = "Ansible SSM file transfers"
  })
}

# Block all public access.
resource "aws_s3_bucket_public_access_block" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enforce bucket-owner ownership; ACLs are disabled.
resource "aws_s3_bucket_ownership_controls" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Encrypt uploaded objects using S3-managed encryption.
resource "aws_s3_bucket_server_side_encryption_configuration" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Deny requests that do not use HTTPS.
resource "aws_s3_bucket_policy" "ansible_ssm" {
  bucket = aws_s3_bucket.ansible_ssm.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          aws_s3_bucket.ansible_ssm.arn,
          "${aws_s3_bucket.ansible_ssm.arn}/*"
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })
}
