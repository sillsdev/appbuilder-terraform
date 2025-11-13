# Deployment Scenarios

This Terraform configuration supports two deployment scenarios using the `deploy_portal` variable.

## Scenario 1: Full Deployment (BuildEngine + Portal)

Deploy both the BuildEngine web service and the Portal website together.

**Configuration:**

```hcl
deploy_portal = true  # This is the default
```

**What gets deployed:**

- VPC and networking
- ECS cluster
- BuildEngine database (MariaDB)
- BuildEngine ECS service
- Portal database (PostgreSQL)
- Portal ECS service
- Valkey/Redis cache
- Application Load Balancer
- All IAM users and policies
- Cloudflare DNS records

**Use case:** Primary installation where the portal needs its own BuildEngine instance.

---

## Scenario 2: BuildEngine Only

Deploy only the BuildEngine web service without the Portal components.

**Configuration:**

```hcl
deploy_portal = false
```

**What gets deployed:**

- VPC and networking
- ECS cluster
- BuildEngine database (MariaDB)
- BuildEngine ECS service
- Application Load Balancer
- BuildEngine IAM users and policies
- S3 buckets for artifacts, secrets, and projects

**What does NOT get deployed:**

- Portal database
- Portal ECS service
- Valkey/Redis cache
- Portal IAM users
- Cloudflare DNS records for portal

**Use case:** Secondary BuildEngine instances that will be connected to a primary Portal deployment.

---

## Implementation Example

### Using terraform.tfvars

```hcl
# Full deployment (default)
deploy_portal = true

# Or BuildEngine only
deploy_portal = false
```

### Using command line

```bash
# Full deployment
terraform apply

# BuildEngine only
terraform apply -var="deploy_portal=false"
```

### Using workspace-specific tfvars files

```bash
# primary-with-portal.tfvars
deploy_portal = true

# secondary-buildengine.tfvars
deploy_portal = false
```

Then apply:

```bash
terraform apply -var-file="primary-with-portal.tfvars"
# or
terraform apply -var-file="secondary-buildengine.tfvars"
```

---

## Migration from Branch-Based Approach

If you previously managed different deployments using separate branches:

1. **Consolidate to a single branch** (e.g., `main` or `master`)
2. **Use tfvars files** for different environments:
   - `primary.tfvars` with `deploy_portal = true`
   - `secondary.tfvars` with `deploy_portal = false`
3. **Use Terraform workspaces** if managing multiple environments:
   ```bash
   terraform workspace new primary
   terraform workspace new secondary-buildengine-1
   terraform workspace new secondary-buildengine-2
   ```

---

## Benefits

✅ **Single source of truth** - One codebase for all deployments  
✅ **Easy maintenance** - Updates apply to all scenarios  
✅ **No branch management overhead** - No need to merge changes between branches  
✅ **Clear configuration** - Deployment type is explicit in variables  
✅ **Version control friendly** - Changes are tracked in one place
