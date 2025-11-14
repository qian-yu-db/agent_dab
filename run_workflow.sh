#!/bin/bash

# Databricks Asset Bundle Workflow Runner for AI Agent Deployment
# Usage: ./run_workflow.sh [--profile PROFILE] [--target TARGET] [OPTIONS]

set -e  # Exit on any error

# Default values
PROFILE=""
TARGET="dev"
SKIP_VALIDATION=false
SKIP_DEPLOYMENT=false
JOB_ID=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to show usage
show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

OPTIONS:
    --profile PROFILE          Databricks profile to use for authentication
    --target TARGET            Deployment target (dev or prod, default: dev)
    --skip-validation          Skip bundle validation step
    --skip-deployment          Skip bundle deployment step
    --job-id JOB_ID           Job ID to run (skip deployment and use existing job)
    --help                     Show this help message

EXAMPLES:
    # Basic usage with defaults
    $0

    # Use specific profile and prod target
    $0 --profile my-profile --target prod

    # Run specific job ID directly
    $0 --job-id 123456 --profile my-profile

    # Skip validation and deployment (use existing deployment)
    $0 --skip-validation --skip-deployment --profile my-profile

WHAT THIS WORKFLOW DOES:
    This workflow deploys an AI agent using the Databricks Agent Framework.

    The agent is a tool-calling agent that:
    - Executes Python code using Unity Catalog functions (system.ai.python_exec)
    - Uses the Claude Sonnet 4 model endpoint (databricks-claude-sonnet-4)
    - Responds to user queries with streaming support
    - Implements MLflow's ResponsesAgent framework

    The deployment workflow:
    1. Validates the bundle configuration (optional, --skip-validation)
    2. Deploys the bundle to target environment (optional, --skip-deployment)
    3. Runs the 'agent_deploy' job which executes src/driver.py:
       a. Tests the agent with sample queries
       b. Logs the agent as an MLflow model
       c. Registers the model to Unity Catalog
       d. Deploys the agent as a serving endpoint

CONFIGURATION:
    • Bundle name: agent_deploy
    • Job name: agent_deploy
    • Default catalog: fins_genai
    • Default schema: agents
    • Workspace: https://e2-demo-field-eng.cloud.databricks.com
    • Required UC function: system.ai.python_exec
    • Required serving endpoint: databricks-claude-sonnet-4

EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --profile)
            PROFILE="$2"
            shift 2
            ;;
        --target)
            TARGET="$2"
            shift 2
            ;;
        --skip-validation)
            SKIP_VALIDATION=true
            shift
            ;;
        --skip-deployment)
            SKIP_DEPLOYMENT=true
            shift
            ;;
        --job-id)
            JOB_ID="$2"
            shift 2
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Validate target
if [[ "$TARGET" != "dev" && "$TARGET" != "prod" ]]; then
    print_error "Invalid target: $TARGET. Must be 'dev' or 'prod'"
    exit 1
fi

# Build profile argument
PROFILE_ARG=""
if [[ -n "$PROFILE" ]]; then
    PROFILE_ARG="--profile $PROFILE"
fi

# Define catalog/schema (these match the defaults in databricks.yml)
CATALOG="fins_genai"
SCHEMA="agents"

print_info "═══════════════════════════════════════════════════════════════════"
print_info "  AI Agent Deployment Workflow"
print_info "═══════════════════════════════════════════════════════════════════"
print_info "Configuration:"
print_info "  • Profile: ${PROFILE:-default}"
print_info "  • Target: $TARGET"
print_info "  • Catalog: $CATALOG"
print_info "  • Schema: $SCHEMA"
print_info "═══════════════════════════════════════════════════════════════════"

# Step 1: Validate bundle (unless skipped or using existing job)
if [[ "$SKIP_VALIDATION" == false && -z "$JOB_ID" ]]; then
    print_info "\n📋 Step 1: Validating Databricks asset bundle..."
    if databricks bundle validate $PROFILE_ARG; then
        print_success "Bundle validation completed successfully!"
    else
        print_error "Bundle validation failed!"
        exit 1
    fi
else
    print_warning "Skipping bundle validation"
fi

# Step 2: Deploy bundle (unless skipped or using existing job)
if [[ "$SKIP_DEPLOYMENT" == false && -z "$JOB_ID" ]]; then
    print_info "\n🚀 Step 2: Deploying Databricks asset bundle to '$TARGET' target..."
    if databricks bundle deploy --target $TARGET $PROFILE_ARG; then
        print_success "Bundle deployed successfully to '$TARGET' target!"
    else
        print_error "Bundle deployment failed!"
        exit 1
    fi
else
    print_warning "Skipping bundle deployment"
fi

# Step 3: Run the workflow
print_info "\n⚡ Step 3: Running the workflow..."

if [[ -n "$JOB_ID" ]]; then
    # Use provided job ID
    print_info "Using provided job ID: $JOB_ID"

    if databricks jobs run-now --job-id $JOB_ID $PROFILE_ARG; then
        print_success "Workflow launched successfully!"
    else
        print_error "Failed to launch workflow!"
        exit 1
    fi
else
    # Use bundle run command
    print_info "Launching workflow via bundle..."
    print_info "Job name: agent_deploy"

    if databricks bundle run agent_deploy --target $TARGET $PROFILE_ARG; then
        print_success "Workflow completed successfully!"
    else
        print_error "Workflow execution failed!"
        exit 1
    fi
fi

print_info "\n═══════════════════════════════════════════════════════════════════"
print_success "🎉 Agent deployment completed successfully!"
print_info "═══════════════════════════════════════════════════════════════════"
print_info "\n📊 Next steps:"
print_info "  • Check the agent model in Unity Catalog: $CATALOG.$SCHEMA"
print_info "  • Test the agent via the Databricks serving endpoint"
print_info "  • View agent logs in MLflow experiments"
print_info "═══════════════════════════════════════════════════════════════════"