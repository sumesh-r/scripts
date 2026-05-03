output "cdn_id" {
  value = aws_cloudfront_distribution.s3_distribution.id
}

output "s3_bucket_name" {
  value = aws_s3_bucket.file_bucket.bucket
}

output "access_key_id" {
  value = aws_iam_access_key.s3_cf_user_keys.id
}

output "secret_access_key" {
  value     = aws_iam_access_key.s3_cf_user_keys.secret
  sensitive = true
}