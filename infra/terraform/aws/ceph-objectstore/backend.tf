terraform {
  cloud {
    organization = "spruyt-labs"
    workspaces {
      name = "spruyt-labs-aws-ceph-objectstore"
    }
  }
}
