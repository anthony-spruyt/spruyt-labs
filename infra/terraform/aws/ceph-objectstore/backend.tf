terraform {
  # terrascan:ignore
  cloud {
    organization = "spruyt-labs"
    workspaces {
      name = "spruyt-labs-aws-ceph-objectstore"
    }
  }
  # terrascan:endignore
}
