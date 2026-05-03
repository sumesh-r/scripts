# CloudFront Distribution for S3 Bucket
resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.client_name}-oac"
  description                       = "S3-OAC"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}


data "aws_cloudfront_function" "existing_function" {
  name    = "nextjs-static-rewrite"
  stage   = "LIVE"
}


resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name              = aws_s3_bucket.file_bucket.bucket_regional_domain_name
    origin_id                = "S3-${aws_s3_bucket.file_bucket.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
    # s3_origin_config {
    #   origin_access_identity = aws_cloudfront_origin_access_identity.oai.cloudfront_access_identity_path
    # }
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "CloudFront distribution for ${var.s3_bucket_name}"
  default_root_object = ""

  # Default cache behavior
  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "S3-${aws_s3_bucket.file_bucket.id}"
    viewer_protocol_policy = "redirect-to-https"

    compress = true

    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6"
    origin_request_policy_id = "88a5eaf4-2fd4-4709-b370-b4c650ea3fcf"

    function_association {
      event_type   = "viewer-request"
      function_arn = data.aws_cloudfront_function.existing_function.arn
    }

  }

  # Price class - Use only North America and Europe
  price_class = "PriceClass_All"

  # Restrict viewer access
  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # Viewer certificate
  viewer_certificate {
    cloudfront_default_certificate = true
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  tags = {
    Name        = "${var.client_name}-cloudfront-distribution"
    Environment = var.client_name
    Terraform   = "true"
  }
}

# S3 Bucket Policy for CloudFront
resource "aws_s3_bucket_policy" "file_bucket" {
  bucket = aws_s3_bucket.file_bucket.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "AllowCloudFrontAccessViaOAC",
        Effect = "Allow",
        Principal = {
          Service = "cloudfront.amazonaws.com"
        },
        Action   = "s3:GetObject",
        Resource = "${aws_s3_bucket.file_bucket.arn}/*",
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = "${aws_cloudfront_distribution.s3_distribution.arn}"
          }
        }
      }
    ]
  })

  depends_on = [aws_s3_bucket_public_access_block.file_bucket]
}
