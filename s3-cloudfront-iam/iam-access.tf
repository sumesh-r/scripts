
# IAM User
resource "aws_iam_user" "s3_cf_user" {
  name = "${var.client_name}-user"
}

# IAM Policy Document
data "aws_iam_policy_document" "s3_cf_policy" {
  statement {
    sid    = "S3FullAccessToSpecificBucket"
    effect = "Allow"

    actions = [
      "s3:*"
    ]

    resources = [
      "arn:aws:s3:::${aws_s3_bucket.file_bucket.bucket}",
      "arn:aws:s3:::${aws_s3_bucket.file_bucket.bucket}/*"
    ]
  }

  statement {
    sid    = "CloudFrontAccessToSpecificDistribution"
    effect = "Allow"

    actions = [
      "cloudfront:GetDistribution",
      "cloudfront:ListDistributions",
      "cloudfront:UpdateDistribution",
      "cloudfront:CreateInvalidation"
    ]

    resources = [
      "${aws_cloudfront_distribution.s3_distribution.arn}"
    ]
  }
}

# Create the IAM Policy
resource "aws_iam_policy" "s3_cf_policy" {
  name        = "S3AndCloudFrontAccessPolicy-${var.client_name}"
  description = "Full access to specific S3 bucket and specific CloudFront distribution"
  policy      = data.aws_iam_policy_document.s3_cf_policy.json
}

# Attach policy to the user
resource "aws_iam_user_policy_attachment" "s3_cf_user_attach" {
  user       = aws_iam_user.s3_cf_user.name
  policy_arn = aws_iam_policy.s3_cf_policy.arn
}

# (Optional) Create Access Keys for the user
resource "aws_iam_access_key" "s3_cf_user_keys" {
  user = aws_iam_user.s3_cf_user.name
}
