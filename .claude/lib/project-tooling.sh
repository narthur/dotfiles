#!/bin/bash
# Project Tooling Detection Library
# Detects test runners, linters, type checkers, and package managers

set -euo pipefail

# Detect package manager
# Usage: detect_package_manager <project_path>
detect_package_manager() {
    local project_path="$1"

    if [[ -f "${project_path}/pnpm-lock.yaml" ]]; then
        echo "pnpm"
    elif [[ -f "${project_path}/yarn.lock" ]]; then
        echo "yarn"
    elif [[ -f "${project_path}/package-lock.json" ]] || [[ -f "${project_path}/package.json" ]]; then
        echo "npm"
    elif [[ -f "${project_path}/Gemfile" ]]; then
        echo "bundle"
    elif [[ -f "${project_path}/go.mod" ]]; then
        echo "go"
    elif [[ -f "${project_path}/composer.json" ]]; then
        echo "composer"
    elif [[ -f "${project_path}/requirements.txt" ]] || [[ -f "${project_path}/setup.py" ]] || [[ -f "${project_path}/pyproject.toml" ]]; then
        echo "pip"
    elif [[ -f "${project_path}/Cargo.toml" ]]; then
        echo "cargo"
    else
        echo "unknown"
    fi
}

# Detect test command
# Usage: detect_test_command <project_path>
detect_test_command() {
    local project_path="$1"
    local pkg_manager
    pkg_manager=$(detect_package_manager "$project_path")

    # Check package.json scripts for Node projects
    if [[ -f "${project_path}/package.json" ]]; then
        if jq -e '.scripts.test' "${project_path}/package.json" >/dev/null 2>&1; then
            echo "${pkg_manager} test"
            return 0
        fi
    fi

    # Ruby/Rails
    if [[ -f "${project_path}/Rakefile" ]] && grep -q "Rails" "${project_path}/Rakefile" 2>/dev/null; then
        echo "bundle exec rails test"
        return 0
    elif [[ -f "${project_path}/Gemfile" ]] && grep -q "rspec" "${project_path}/Gemfile" 2>/dev/null; then
        echo "bundle exec rspec"
        return 0
    fi

    # Go
    if [[ -f "${project_path}/go.mod" ]]; then
        echo "go test ./..."
        return 0
    fi

    # Python
    if [[ -f "${project_path}/pytest.ini" ]] || [[ -f "${project_path}/setup.cfg" ]] || grep -q "pytest" "${project_path}/requirements.txt" 2>/dev/null; then
        echo "pytest"
        return 0
    elif [[ -f "${project_path}/setup.py" ]]; then
        echo "python -m unittest discover"
        return 0
    fi

    # Rust
    if [[ -f "${project_path}/Cargo.toml" ]]; then
        echo "cargo test"
        return 0
    fi

    # PHP
    if [[ -f "${project_path}/phpunit.xml" ]] || [[ -f "${project_path}/phpunit.xml.dist" ]]; then
        echo "vendor/bin/phpunit"
        return 0
    fi

    echo "none"
}

# Detect lint command
# Usage: detect_lint_command <project_path>
detect_lint_command() {
    local project_path="$1"
    local pkg_manager
    pkg_manager=$(detect_package_manager "$project_path")

    # Check package.json scripts for Node projects
    if [[ -f "${project_path}/package.json" ]]; then
        if jq -e '.scripts.lint' "${project_path}/package.json" >/dev/null 2>&1; then
            echo "${pkg_manager} run lint"
            return 0
        fi

        # Check for eslint config
        if [[ -f "${project_path}/.eslintrc.js" ]] || [[ -f "${project_path}/.eslintrc.json" ]] || [[ -f "${project_path}/eslint.config.js" ]]; then
            echo "${pkg_manager} exec eslint ."
            return 0
        fi
    fi

    # Ruby
    if [[ -f "${project_path}/.rubocop.yml" ]]; then
        echo "bundle exec rubocop"
        return 0
    fi

    # Go
    if [[ -f "${project_path}/go.mod" ]]; then
        echo "golangci-lint run"
        return 0
    fi

    # Python
    if [[ -f "${project_path}/.flake8" ]] || [[ -f "${project_path}/setup.cfg" ]]; then
        echo "flake8"
        return 0
    elif [[ -f "${project_path}/pyproject.toml" ]] && grep -q "ruff" "${project_path}/pyproject.toml" 2>/dev/null; then
        echo "ruff check"
        return 0
    fi

    # Rust
    if [[ -f "${project_path}/Cargo.toml" ]]; then
        echo "cargo clippy"
        return 0
    fi

    echo "none"
}

# Detect type check command
# Usage: detect_typecheck_command <project_path>
detect_typecheck_command() {
    local project_path="$1"
    local pkg_manager
    pkg_manager=$(detect_package_manager "$project_path")

    # TypeScript
    if [[ -f "${project_path}/tsconfig.json" ]]; then
        if [[ -f "${project_path}/package.json" ]] && jq -e '.scripts.typecheck' "${project_path}/package.json" >/dev/null 2>&1; then
            echo "${pkg_manager} run typecheck"
            return 0
        else
            echo "${pkg_manager} exec tsc --noEmit"
            return 0
        fi
    fi

    # Python with mypy
    if [[ -f "${project_path}/mypy.ini" ]] || grep -q "mypy" "${project_path}/requirements.txt" 2>/dev/null; then
        echo "mypy ."
        return 0
    fi

    echo "none"
}

# Detect format check command
# Usage: detect_format_command <project_path>
detect_format_command() {
    local project_path="$1"
    local pkg_manager
    pkg_manager=$(detect_package_manager "$project_path")

    # Prettier
    if [[ -f "${project_path}/.prettierrc" ]] || [[ -f "${project_path}/.prettierrc.json" ]] || [[ -f "${project_path}/prettier.config.js" ]]; then
        if [[ -f "${project_path}/package.json" ]] && jq -e '.scripts.format' "${project_path}/package.json" >/dev/null 2>&1; then
            echo "${pkg_manager} run format:check"
            return 0
        else
            echo "${pkg_manager} exec prettier --check ."
            return 0
        fi
    fi

    # Black (Python)
    if grep -q "black" "${project_path}/requirements.txt" 2>/dev/null || [[ -f "${project_path}/pyproject.toml" ]] && grep -q "black" "${project_path}/pyproject.toml" 2>/dev/null; then
        echo "black --check ."
        return 0
    fi

    # Rustfmt
    if [[ -f "${project_path}/Cargo.toml" ]]; then
        echo "cargo fmt -- --check"
        return 0
    fi

    # gofmt
    if [[ -f "${project_path}/go.mod" ]]; then
        echo "gofmt -l ."
        return 0
    fi

    echo "none"
}

# Get all quality check commands for a project
# Usage: get_quality_commands <project_path>
# Output: JSON object with test, lint, typecheck, format commands
get_quality_commands() {
    local project_path="$1"

    local test_cmd
    test_cmd=$(detect_test_command "$project_path")
    local lint_cmd
    lint_cmd=$(detect_lint_command "$project_path")
    local typecheck_cmd
    typecheck_cmd=$(detect_typecheck_command "$project_path")
    local format_cmd
    format_cmd=$(detect_format_command "$project_path")
    local pkg_manager
    pkg_manager=$(detect_package_manager "$project_path")

    jq -n \
        --arg test "$test_cmd" \
        --arg lint "$lint_cmd" \
        --arg typecheck "$typecheck_cmd" \
        --arg format "$format_cmd" \
        --arg pkg_manager "$pkg_manager" \
        '{
            package_manager: $pkg_manager,
            test: $test,
            lint: $lint,
            typecheck: $typecheck,
            format: $format
        }'
}

# Run quality checks and return results
# Usage: run_quality_checks <project_path>
# Output: JSON with results for each check
run_quality_checks() {
    local project_path="$1"

    cd "$project_path"

    local commands
    commands=$(get_quality_commands "$project_path")

    local test_cmd
    test_cmd=$(echo "$commands" | jq -r '.test')
    local lint_cmd
    lint_cmd=$(echo "$commands" | jq -r '.lint')
    local typecheck_cmd
    typecheck_cmd=$(echo "$commands" | jq -r '.typecheck')
    local format_cmd
    format_cmd=$(echo "$commands" | jq -r '.format')

    local results='{}'

    # Run tests
    if [[ "$test_cmd" != "none" ]]; then
        if $test_cmd >/dev/null 2>&1; then
            results=$(echo "$results" | jq '.test = {status: "pass", command: $cmd}' --arg cmd "$test_cmd")
        else
            results=$(echo "$results" | jq '.test = {status: "fail", command: $cmd}' --arg cmd "$test_cmd")
        fi
    else
        results=$(echo "$results" | jq '.test = {status: "skip", command: "none"}')
    fi

    # Run linter
    if [[ "$lint_cmd" != "none" ]]; then
        if $lint_cmd >/dev/null 2>&1; then
            results=$(echo "$results" | jq '.lint = {status: "pass", command: $cmd}' --arg cmd "$lint_cmd")
        else
            results=$(echo "$results" | jq '.lint = {status: "fail", command: $cmd}' --arg cmd "$lint_cmd")
        fi
    else
        results=$(echo "$results" | jq '.lint = {status: "skip", command: "none"}')
    fi

    # Run type checker
    if [[ "$typecheck_cmd" != "none" ]]; then
        if $typecheck_cmd >/dev/null 2>&1; then
            results=$(echo "$results" | jq '.typecheck = {status: "pass", command: $cmd}' --arg cmd "$typecheck_cmd")
        else
            results=$(echo "$results" | jq '.typecheck = {status: "fail", command: $cmd}' --arg cmd "$typecheck_cmd")
        fi
    else
        results=$(echo "$results" | jq '.typecheck = {status: "skip", command: "none"}')
    fi

    # Run formatter check
    if [[ "$format_cmd" != "none" ]]; then
        if $format_cmd >/dev/null 2>&1; then
            results=$(echo "$results" | jq '.format = {status: "pass", command: $cmd}' --arg cmd "$format_cmd")
        else
            results=$(echo "$results" | jq '.format = {status: "fail", command: $cmd}' --arg cmd "$format_cmd")
        fi
    else
        results=$(echo "$results" | jq '.format = {status: "skip", command: "none"}')
    fi

    echo "$results"
}

# Export functions
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    export -f detect_package_manager detect_test_command detect_lint_command
    export -f detect_typecheck_command detect_format_command get_quality_commands
    export -f run_quality_checks
fi
