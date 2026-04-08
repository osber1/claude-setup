---
name: spock
description: Spock testing framework best practices for Groovy/Java — test structure, mocking with Stub/Mock, data-driven tests, naming conventions, and anti-patterns. Use when writing or reviewing Spock specs, or when user asks about Spock tests.
metadata:
  version: "1.0.0"
  domain: testing
  triggers: Spock, Spock 2.x, Groovy test, Test, Specification, extends Specification, Stub(), Mock(), where block, data-driven test, BDD Groovy
  role: specialist
  scope: implementation
  output-format: code
---

# Spock Testing Framework Skill

Write and review Spock tests following established best practices.

## When to Use
- Writing new Spock specs
- Reviewing existing Spock tests
- "write a test" / "add a spec" / "test this with Spock"
- Fixing or improving existing Spock tests

---

## Basic Test Structure

```groovy
class MySpec extends Specification {
    // Constants at the top - clear and simple
    static final DATE_NOW = today()

    static final String TEST_ID = 'test-id'

    // Test objects without private/final - cleaner Groovy style
    Request request = new Request(id: TEST_ID)

    // Mocks/Stubs - using appropriate type for the use case
    RequestValidator validator = Stub()

    EventService eventService = Mock()

    // Subject with concise initialization
    @Subject
    Handler handler = [validator, eventService]
}
```

## Test Method Patterns

1. Simple Validation Test:

```groovy
void 'should validate when condition'() {
    given:
        validator.isValid(request) >> true
    when:
        boolean result = handler.process(request)
    then:
        result
    and:
        1 * eventService.log(request)
}
```

2. Data-Driven Test (no @Unroll needed — unrolling is default in Spock 2.x):

```groovy
void 'should handle #scenario'() {
    given:
        validator.isValid(request) >> valid
    expect:
        handler.process(request) == expected
    where:
        scenario        | valid  || expected
        'valid case'    | true   || true
        'invalid case'  | false  || false
}
```

3. Exception Test:

```groovy
void 'should throw exception when validation fails'() {
    given:
        validator.isValid(request) >> { throw new ValidationException() }
    when:
        handler.process(request)
    then:
        thrown(ValidationException)
    and:
        0 * eventService._
}
```

## Best Practices

### Test Structure
- Constants at the top with `static final`
- Test objects without `private`/`final` modifiers
- Clear separation between setup objects and mocks
- Concise `@Subject` initialization
- Use meaningful names for all elements

### Blocks Usage
- Use clean block separation with consistent spacing
- Use `and:` for related verifications
- Keep `given:` blocks focused on setup
- Verify both positive and negative interactions
- Prefer `expect:` over `given/when/then` whenever possible — inline simple setup directly into the `expect:` expression (e.g. `expect: foo([a: 1, b: 2]) == 3`). Only use `given:` when the setup is non-trivial (e.g. mutating a field on an object before asserting)

### Mocking Best Practices
- Use `Stub()` for query/lookup behavior
- Use `Mock()` for interaction verification
- Verify zero interactions with `0 * service._`
- Group related verifications under `and:`

### Test Data
- Keep test data simple and clear
- Use map-style initialization where appropriate
- Constants should be meaningful and well-named
- Use builders or helper methods for complex objects

### Naming Conventions
- Use single quotes for test names
- Follow `should ... when ...` pattern: `'should return null when input is empty'`
- Include scenario description in data-driven tests
- Keep names concise but clear

## Example Full Test

```groovy
class RequestHandlerSpec extends Specification {
    static final String REQUEST_ID = 'test-123'
    static final LocalDate DATE = LocalDate.now()

    Request request = new Request(id: REQUEST_ID, date: DATE)
    ValidationService validator = Stub()
    EventLogger eventLogger = Mock()

    @Subject
    RequestHandler handler = [validator, eventLogger]

    void 'should process valid request'() {
        given:
            validator.isValid(request) >> true
        when:
            Response response = handler.process(request)
        then:
            response.success
        and:
            1 * eventLogger.log(request)
    }
}
```

## Anti-Patterns to Avoid

- Using `@Unroll` — not needed in Spock, unrolling is the default behavior
- Using `def` instead of explicit types — always declare the full type (e.g. `String name = ...`, `List<Foo> items = ...`)
- Unnecessary `private`/`final` modifiers in tests
- Complex test setup
- Multiple behaviors in a single test
- Unclear test names
- Missing verification blocks
- Overuse of mocking
- Unnecessary helper methods
- Complex test data
- Missing edge cases

## Code Style

- Use single quotes for strings
- Use map-style initialization where appropriate
- Keep one assertion per test
- Use clear block separation
- Group related verifications under `and:`
- Use consistent spacing
- Keep tests focused and readable
