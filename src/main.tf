data "google_project" "this" {
    project_id = var.project_id
}

provider "google" {
  project = var.project_id
}
