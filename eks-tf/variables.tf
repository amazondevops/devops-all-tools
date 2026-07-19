variable "region" {
  default = "eu-west-1"
}

variable "cluster_name" {
  default = "poc-eks"
}

variable "cluster_version" {
  default = "1.35"
}

variable "private_subnet_ids" {
  type = list(string)
  default = [
    "subnet-00646c4c7b71d7e24", # eu-west-1a
    "subnet-09d82a77490fbd360", # eu-west-1b
    "subnet-0d9222b53e6143433", # eu-west-1c
  ]
}

variable "public_subnet_ids" {
  type = list(string)
  default = [
    "subnet-0214e2345846a0716", # eu-west-1a
    "subnet-0eafa8ab43abb2a4a", # eu-west-1b
    "subnet-09c2446717af07fd7", # eu-west-1c
  ]
}
variable "vpc_id" {
  default = "vpc-0640d228b573c9490"
}