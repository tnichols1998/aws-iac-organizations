#!/bin/bash

# LocalStack Setup and Management Script
# Provides commands to start, stop, and inspect LocalStack for development

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
LOCALSTACK_VERSION="latest"
LOCALSTACK_PORT="4566"
COMPOSE_FILE="$(dirname "$0")/../docker-compose.localstack.yml"

# Helper functions
log_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

log_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

log_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Check if Docker is running
check_docker() {
    if ! docker info >/dev/null 2>&1; then
        log_error "Docker is not running. Please start Docker Desktop and try again."
        exit 1
    fi
}

# Check if LocalStack is running
is_localstack_running() {
    curl -s http://localhost:$LOCALSTACK_PORT/health >/dev/null 2>&1
}

# Start LocalStack
start_localstack() {
    log_info "Starting LocalStack..."
    
    check_docker
    
    if is_localstack_running; then
        log_warning "LocalStack is already running"
        return 0
    fi
    
    # Create docker-compose file if it doesn't exist
    if [ ! -f "$COMPOSE_FILE" ]; then
        create_compose_file
    fi
    
    # Start LocalStack using docker-compose
    docker-compose -f "$COMPOSE_FILE" up -d
    
    # Wait for LocalStack to be ready
    log_info "Waiting for LocalStack to be ready..."
    max_attempts=30
    attempt=0
    
    while [ $attempt -lt $max_attempts ]; do
        if is_localstack_running; then
            log_success "LocalStack is running at http://localhost:$LOCALSTACK_PORT"
            return 0
        fi
        
        sleep 2
        attempt=$((attempt + 1))
        echo -n "."
    done
    
    log_error "LocalStack failed to start after $max_attempts attempts"
    return 1
}

# Stop LocalStack
stop_localstack() {
    log_info "Stopping LocalStack..."
    
    if [ -f "$COMPOSE_FILE" ]; then
        docker-compose -f "$COMPOSE_FILE" down
    else
        # Fallback to stopping by container name
        docker stop localstack-main >/dev/null 2>&1 || true
        docker rm localstack-main >/dev/null 2>&1 || true
    fi
    
    log_success "LocalStack stopped"
}

# Create docker-compose file for LocalStack
create_compose_file() {
    log_info "Creating LocalStack docker-compose configuration..."
    
    cat > "$COMPOSE_FILE" << 'EOF'
version: '3.8'

services:
  localstack:
    container_name: localstack-main
    image: localstack/localstack:latest
    ports:
      - "4566:4566"
    environment:
      - SERVICES=organizations,iam,s3,cloudtrail,guardduty,securityhub,config,sts,cloudformation,logs
      - DEBUG=1
      - DATA_DIR=/tmp/localstack/data
      - DOCKER_HOST=unix:///var/run/docker.sock
      - HOST_TMP_FOLDER=${TMPDIR}
    volumes:
      - "${TMPDIR:-/tmp}/localstack:/tmp/localstack"
      - "/var/run/docker.sock:/var/run/docker.sock"
    networks:
      - localstack-net

networks:
  localstack-net:
    name: localstack-network
EOF
    
    log_success "Created docker-compose configuration at $COMPOSE_FILE"
}

# Inspect LocalStack resources
inspect_localstack() {
    log_info "Inspecting LocalStack resources..."
    
    if ! is_localstack_running; then
        log_error "LocalStack is not running. Start it with: $0 start"
        return 1
    fi
    
    echo
    log_info "=== LocalStack Health ==="
    curl -s http://localhost:$LOCALSTACK_PORT/health | jq . || curl -s http://localhost:$LOCALSTACK_PORT/health
    
    echo
    log_info "=== Organizations ==="
    echo "Listing organizations:"
    aws --endpoint-url=http://localhost:$LOCALSTACK_PORT organizations list-roots --region us-east-1 2>/dev/null || echo "No organizations found or service not available"
    
    echo
    log_info "=== S3 Buckets ==="
    aws --endpoint-url=http://localhost:$LOCALSTACK_PORT s3 ls --region us-east-1 2>/dev/null || echo "No buckets found"
    
    echo
    log_success "LocalStack inspection complete"
}

# Reset LocalStack (stop, remove data, start)
reset_localstack() {
    log_warning "Resetting LocalStack (this will destroy all data)..."
    
    stop_localstack
    
    # Remove LocalStack data
    log_info "Removing LocalStack data..."
    rm -rf "${TMPDIR:-/tmp}/localstack" >/dev/null 2>&1 || true
    
    # Start fresh
    start_localstack
    
    log_success "LocalStack reset complete"
}

# Show LocalStack logs
logs_localstack() {
    if [ -f "$COMPOSE_FILE" ]; then
        docker-compose -f "$COMPOSE_FILE" logs -f localstack
    else
        docker logs -f localstack-main 2>/dev/null || log_error "LocalStack container not found"
    fi
}

# Main command handling
case "${1:-help}" in
    start)
        start_localstack
        ;;
    stop)
        stop_localstack
        ;;
    restart)
        stop_localstack
        start_localstack
        ;;
    inspect)
        inspect_localstack
        ;;
    reset)
        reset_localstack
        ;;
    logs)
        logs_localstack
        ;;
    status)
        if is_localstack_running; then
            log_success "LocalStack is running at http://localhost:$LOCALSTACK_PORT"
        else
            log_warning "LocalStack is not running"
        fi
        ;;
    help|*)
        echo "Usage: $0 {start|stop|restart|inspect|reset|logs|status}"
        echo
        echo "Commands:"
        echo "  start    - Start LocalStack for development"
        echo "  stop     - Stop LocalStack"
        echo "  restart  - Restart LocalStack"
        echo "  inspect  - Show LocalStack resources and health"
        echo "  reset    - Reset LocalStack (destroys all data)"
        echo "  logs     - Show LocalStack logs"
        echo "  status   - Check if LocalStack is running"
        echo
        exit 1
        ;;
esac
