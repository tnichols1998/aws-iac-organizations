#!/usr/bin/env python3
"""
Configuration Validation Script
Validates organization YAML configuration files against expected schema
"""

import sys
import argparse
import yaml
from pathlib import Path
from typing import Dict, List, Any, Optional
import re


class ConfigValidator:
    """Validates organization configuration files"""
    
    def __init__(self):
        self.errors = []
        self.warnings = []
    
    def validate_file(self, config_path: str) -> bool:
        """Validate a configuration file"""
        try:
            config_file = Path(config_path)
            if not config_file.exists():
                self.errors.append(f"Configuration file not found: {config_path}")
                return False
            
            with open(config_file, 'r') as f:
                config = yaml.safe_load(f)
            
            return self.validate_config(config)
            
        except yaml.YAMLError as e:
            self.errors.append(f"YAML parsing error: {e}")
            return False
        except Exception as e:
            self.errors.append(f"Unexpected error: {e}")
            return False
    
    def validate_config(self, config: Dict[str, Any]) -> bool:
        """Validate the parsed configuration"""
        self.errors = []
        self.warnings = []
        
        # Check required top-level sections
        required_sections = ['metadata', 'environments', 'organization', 'organizational_units', 'accounts']
        for section in required_sections:
            if section not in config:
                self.errors.append(f"Missing required section: {section}")
        
        # Validate each section
        if 'metadata' in config:
            self.validate_metadata(config['metadata'])
        
        if 'environments' in config:
            self.validate_environments(config['environments'])
        
        if 'organization' in config:
            self.validate_organization(config['organization'])
        
        if 'organizational_units' in config:
            self.validate_organizational_units(config['organizational_units'])
        
        if 'accounts' in config:
            self.validate_accounts(config['accounts'], config.get('organizational_units', []))
        
        if 'policies' in config:
            self.validate_policies(config['policies'])
        
        if 'sso' in config:
            self.validate_sso(config['sso'])
        
        if 'github_actions' in config:
            self.validate_github_actions(config['github_actions'])
        
        return len(self.errors) == 0
    
    def validate_metadata(self, metadata: Dict[str, Any]):
        """Validate metadata section"""
        required_fields = ['name', 'description']
        for field in required_fields:
            if field not in metadata:
                self.errors.append(f"metadata.{field} is required")
            elif not isinstance(metadata[field], str) or not metadata[field].strip():
                self.errors.append(f"metadata.{field} must be a non-empty string")
        
        # Validate name format (should be suitable for resource naming)
        if 'name' in metadata:
            name = metadata['name']
            if not re.match(r'^[a-zA-Z0-9-_]+$', name):
                self.errors.append("metadata.name should contain only alphanumeric characters, hyphens, and underscores")
    
    def validate_environments(self, environments: Dict[str, Any]):
        """Validate environments section"""
        required_envs = ['dev', 'qa', 'prod']
        for env in required_envs:
            if env not in environments:
                self.warnings.append(f"Missing recommended environment: {env}")
        
        for env_name, env_config in environments.items():
            if not isinstance(env_config, dict):
                self.errors.append(f"environments.{env_name} must be an object")
                continue
            
            # Validate required fields
            if 'target' not in env_config:
                self.errors.append(f"environments.{env_name}.target is required")
            elif env_config['target'] not in ['aws', 'localstack']:
                self.errors.append(f"environments.{env_name}.target must be 'aws' or 'localstack'")
            
            if 'region' not in env_config:
                self.errors.append(f"environments.{env_name}.region is required")
            
            # For AWS targets, profile should be specified
            if env_config.get('target') == 'aws' and 'profile' not in env_config:
                self.warnings.append(f"environments.{env_name}.profile recommended for AWS targets")
    
    def validate_organization(self, org_config: Dict[str, Any]):
        """Validate organization section"""
        required_fields = ['feature_set', 'default_region', 'allowed_regions']
        for field in required_fields:
            if field not in org_config:
                self.errors.append(f"organization.{field} is required")
        
        # Validate feature_set
        if 'feature_set' in org_config and org_config['feature_set'] not in ['ALL', 'CONSOLIDATED_BILLING']:
            self.errors.append("organization.feature_set must be 'ALL' or 'CONSOLIDATED_BILLING'")
        
        # Validate regions
        if 'allowed_regions' in org_config:
            if not isinstance(org_config['allowed_regions'], list):
                self.errors.append("organization.allowed_regions must be a list")
            else:
                for region in org_config['allowed_regions']:
                    if not re.match(r'^[a-z0-9-]+$', region):
                        self.errors.append(f"Invalid region format: {region}")
        
        # Validate default_region is in allowed_regions
        if 'default_region' in org_config and 'allowed_regions' in org_config:
            if org_config['default_region'] not in org_config['allowed_regions']:
                self.errors.append("organization.default_region must be in allowed_regions")
    
    def validate_organizational_units(self, ous: List[Dict[str, Any]]):
        """Validate organizational units"""
        if not isinstance(ous, list):
            self.errors.append("organizational_units must be a list")
            return
        
        ou_names = set()
        for i, ou in enumerate(ous):
            if not isinstance(ou, dict):
                self.errors.append(f"organizational_units[{i}] must be an object")
                continue
            
            if 'name' not in ou:
                self.errors.append(f"organizational_units[{i}].name is required")
            else:
                name = ou['name']
                if name in ou_names:
                    self.errors.append(f"Duplicate OU name: {name}")
                ou_names.add(name)
                
                # Validate name format
                if not re.match(r'^[a-zA-Z0-9-_\s]+$', name):
                    self.errors.append(f"OU name '{name}' contains invalid characters")
    
    def validate_accounts(self, accounts: List[Dict[str, Any]], ous: List[Dict[str, Any]]):
        """Validate accounts section"""
        if not isinstance(accounts, list):
            self.errors.append("accounts must be a list")
            return
        
        ou_names = {ou['name'] for ou in ous if isinstance(ou, dict) and 'name' in ou}
        account_names = set()
        account_emails = set()
        
        for i, account in enumerate(accounts):
            if not isinstance(account, dict):
                self.errors.append(f"accounts[{i}] must be an object")
                continue
            
            # Validate required fields
            if 'name' not in account:
                self.errors.append(f"accounts[{i}].name is required")
            
            # Require either email or email_template
            has_email = 'email' in account
            has_email_template = 'email_template' in account
            if not has_email and not has_email_template:
                self.errors.append(f"accounts[{i}] must have either 'email' or 'email_template'")
            elif has_email and has_email_template:
                self.errors.append(f"accounts[{i}] cannot have both 'email' and 'email_template'")
            
            # Validate name uniqueness
            if 'name' in account:
                name = account['name']
                if name in account_names:
                    self.errors.append(f"Duplicate account name: {name}")
                account_names.add(name)
                
                # Validate name format
                if not re.match(r'^[a-zA-Z0-9-_]+$', name):
                    self.errors.append(f"Account name '{name}' should contain only alphanumeric characters, hyphens, and underscores")
            
            # Validate email uniqueness and format
            email_to_check = None
            if 'email' in account:
                email_to_check = account['email']
            elif 'email_template' in account:
                # For templates, validate the template format and generate a test email
                template = account['email_template']
                if '{env}' not in template:
                    self.errors.append(f"email_template must contain '{{env}}' placeholder: {template}")
                else:
                    # Generate test email for uniqueness check
                    email_to_check = template.replace('{env}', 'test')
            
            if email_to_check:
                if email_to_check in account_emails:
                    self.errors.append(f"Duplicate account email/template: {email_to_check}")
                account_emails.add(email_to_check)
                
                # Basic email validation
                if not re.match(r'^[^@]+@[^@]+\.[^@]+$', email_to_check):
                    self.errors.append(f"Invalid email format: {email_to_check}")
            
            # Validate OU reference
            if 'ou' in account:
                ou = account['ou']
                if ou not in ou_names:
                    self.errors.append(f"Account '{account.get('name', 'unknown')}' references unknown OU: {ou}")
    
    def validate_policies(self, policies: Dict[str, Any]):
        """Validate policies section"""
        if 'tag_policies' in policies:
            tag_policies = policies['tag_policies']
            if not isinstance(tag_policies, list):
                self.errors.append("policies.tag_policies must be a list")
            else:
                for i, policy in enumerate(tag_policies):
                    if not isinstance(policy, dict):
                        self.errors.append(f"policies.tag_policies[{i}] must be an object")
                    elif 'name' not in policy:
                        self.errors.append(f"policies.tag_policies[{i}].name is required")
        
        if 'service_control_policies' in policies:
            scp_policies = policies['service_control_policies']
            if not isinstance(scp_policies, list):
                self.errors.append("policies.service_control_policies must be a list")
    
    def validate_sso(self, sso_config: Dict[str, Any]):
        """Validate SSO configuration"""
        if not isinstance(sso_config, dict):
            self.errors.append("sso must be an object")
            return
        
        if 'enabled' in sso_config and not isinstance(sso_config['enabled'], bool):
            self.errors.append("sso.enabled must be a boolean")
        
        if 'permission_sets' in sso_config:
            permission_sets = sso_config['permission_sets']
            if not isinstance(permission_sets, list):
                self.errors.append("sso.permission_sets must be a list")
            else:
                for i, ps in enumerate(permission_sets):
                    if not isinstance(ps, dict):
                        self.errors.append(f"sso.permission_sets[{i}] must be an object")
                    elif 'name' not in ps:
                        self.errors.append(f"sso.permission_sets[{i}].name is required")
    
    def validate_github_actions(self, github_config: Dict[str, Any]):
        """Validate GitHub Actions configuration"""
        if not isinstance(github_config, dict):
            self.errors.append("github_actions must be an object")
            return
        
        if 'enabled' in github_config and not isinstance(github_config['enabled'], bool):
            self.errors.append("github_actions.enabled must be a boolean")
        
        if 'repositories' in github_config:
            repos = github_config['repositories']
            if not isinstance(repos, list):
                self.errors.append("github_actions.repositories must be a list")
            else:
                for i, repo in enumerate(repos):
                    if isinstance(repo, dict) and 'repo' in repo:
                        # Validate repo format (org/repo)
                        if not re.match(r'^[a-zA-Z0-9-_.]+/[a-zA-Z0-9-_.]+$', repo['repo']):
                            self.errors.append(f"github_actions.repositories[{i}].repo has invalid format (should be 'org/repo')")
    
    def print_results(self):
        """Print validation results"""
        if self.errors:
            print("❌ Configuration validation failed!")
            print()
            print("Errors:")
            for error in self.errors:
                print(f"  • {error}")
        
        if self.warnings:
            print()
            print("Warnings:")
            for warning in self.warnings:
                print(f"  ⚠️  {warning}")
        
        if not self.errors:
            if self.warnings:
                print("✅ Configuration is valid (with warnings)")
            else:
                print("✅ Configuration is valid!")
            print()


def main():
    parser = argparse.ArgumentParser(description='Validate organization configuration files')
    parser.add_argument('config_file', help='Path to configuration YAML file')
    parser.add_argument('--strict', action='store_true', help='Treat warnings as errors')
    
    args = parser.parse_args()
    
    validator = ConfigValidator()
    is_valid = validator.validate_file(args.config_file)
    
    validator.print_results()
    
    # Exit with appropriate code
    if not is_valid:
        sys.exit(1)
    elif args.strict and validator.warnings:
        print("❌ Validation failed due to warnings (strict mode)")
        sys.exit(1)
    else:
        sys.exit(0)


if __name__ == '__main__':
    main()
