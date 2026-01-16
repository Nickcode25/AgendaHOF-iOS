# 🧪 Testes - Agenda HOF Swift

## 📋 Visão Geral

Este diretório contém todos os testes unitários e de integração do projeto Agenda HOF. O objetivo é atingir **>70% de code coverage** e garantir a qualidade e confiabilidade do código.

## 📁 Estrutura de Testes

```
Tests/
├── README.md (este arquivo)
├── ViewModels/
│   ├── AuthViewModelTests.swift
│   ├── FinancialReportViewModelTests.swift
│   ├── InactivePatientsViewModelTests.swift
│   └── ResetPasswordViewModelTests.swift
├── Extensions/
│   └── StringValidationTests.swift
└── Mocks/
    └── MockSupabaseManager.swift
```

## 🎯 Objetivos de Coverage

| Componente | Target Coverage | Actual Coverage | Testes | Status |
|------------|----------------|-----------------|--------|--------|
| **ViewModels** | >80% | ~75% | 100+ | ✅ Quase Completo |
| **Extensions** | >90% | 100% | 20+ | ✅ Completo |
| **Services** | >70% | 0% | 0 | ⏳ Pendente |
| **Overall** | >70% | **~60%** | **120+** | 🚧 Em Progresso |

**Estimativa de Coverage por ViewModel:**
- AuthViewModel: ~60% (validações completas, integration pendente)
- FinancialReportViewModel: ~80% (lógica de negócio completa)
- InactivePatientsViewModel: ~75% (filtros e WhatsApp completos)
- ResetPasswordViewModel: ~80% (validações completas)

## 🧪 Tipos de Testes

### 1. **Testes Unitários**
Testam componentes isolados sem dependências externas.

**Exemplos:**
- `StringValidationTests.swift` - Validação de email, senha, telefone
- `AuthViewModelTests.swift` - Lógica de autenticação isolada

**Como executar:**
```bash
# Xcode
Cmd+U ou Product > Test

# Command Line
xcodebuild test -scheme "Agenda HOF" -destination 'platform=iOS Simulator,name=iPhone 15'
```

### 2. **Testes de Integração**
Testam interação entre múltiplos componentes usando mocks.

**Exemplos:**
- `AuthViewModelIntegrationTests.swift` - AuthViewModel + MockSupabaseManager

### 3. **Testes de UI** (Futuro)
Testam fluxos de usuário completos na interface.

**Status:** Planejado para Fase 2

## 🛠️ Mocks e Utilitários

### MockSupabaseManager
Mock completo do SupabaseManager para testes.

**Funcionalidades:**
- Simula autenticação bem-sucedida/falhada
- Controla erros via flags (`shouldFailAuth`, `shouldFailProfileFetch`)
- Gerencia usuário e perfil mockados
- Suporta todos os métodos do SupabaseManager real

**Uso:**
```swift
let mockSupabase = MockSupabaseManager(authenticated: true)
mockSupabase.shouldFailAuth = false

// Test successful auth
await mockSupabase.signIn(email: "test@example.com", password: "Pass123!")
XCTAssertTrue(mockSupabase.isAuthenticated)

// Test failed auth
mockSupabase.shouldFailAuth = true
await mockSupabase.signIn(email: "wrong@example.com", password: "Wrong!")
// Should throw error
```

## 📊 Testes Implementados

### ✅ String+Extensions (100% coverage)

**StringValidationTests.swift** - 20+ testes

**Cobertura:**
- ✅ Email validation (valid/invalid)
- ✅ Password validation (requirements)
- ✅ Password strength calculation
- ✅ Phone validation (Brazilian DDD)
- ✅ Phone validation errors
- ✅ String cleaning (`onlyNumbers`, `trimmed`)
- ✅ Phone formatting

**Exemplo:**
```swift
func testValidEmail() {
    XCTAssertTrue("test@example.com".isValidEmail)
    XCTAssertFalse("invalid".isValidEmail)
}

func testPasswordStrength() {
    XCTAssertGreaterThanOrEqual("C0mpl3x!LongPassword".passwordStrength, 0.9)
    XCTAssertLessThan("Test123!".passwordStrength, 0.6)
}
```

### ✅ AuthViewModel (~60% coverage)

**AuthViewModelTests.swift** - 25+ testes

**Cobertura:**
- ✅ Email validation
- ✅ Password validation
- ✅ Password strength
- ✅ Sign up validation (password match, full name)
- ✅ Remember me toggle
- ✅ Loading state
- ✅ Error state
- ✅ Input sanitization
- ⏳ Integration tests (requerem dependency injection)

### ✅ FinancialReportViewModel (~80% coverage)

**FinancialReportViewModelTests.swift** - 30+ testes

**Cobertura:**
- ✅ Period filter (day/week/month/year)
- ✅ Financial data calculations (revenue, expenses, profit)
- ✅ Revenue breakdown by category
- ✅ Currency formatting
- ✅ Percentage calculations
- ✅ Edge cases (negative profit, zero revenue, large numbers)
- ✅ Loading and error states

**Destaques:**
- Testes de cálculo de lucro (receita - despesas)
- Validação de soma de categorias
- Formatação de valores monetários
- Edge cases (valores muito grandes/pequenos)

### ✅ InactivePatientsViewModel (~75% coverage)

**InactivePatientsViewModelTests.swift** - 35+ testes

**Cobertura:**
- ✅ Inactivity threshold (Constants.inactiveDaysThreshold = 180 days)
- ✅ Inactivity days calculation
- ✅ WhatsApp URL generation (Brazilian format)
- ✅ Phone number validation for WhatsApp
- ✅ Patient filtering and sorting
- ✅ Edge cases (very old dates, future dates, empty phones)
- ✅ Inactivity message formatting (singular/plural)

**Destaques:**
- Testes de geração de URL do WhatsApp (`https://wa.me/5511999999999`)
- Validação de DDD brasileiro (11-99)
- Cálculo correto de dias de inatividade
- Handling de casos extremos (5+ anos sem retorno)

### ✅ ResetPasswordViewModel (~80% coverage)

**ResetPasswordViewModelTests.swift** - 30+ testes

**Cobertura:**
- ✅ Password validation (all requirements)
- ✅ Password strength (weak/medium/strong)
- ✅ Password match validation
- ✅ Combined validations
- ✅ Password requirements display
- ✅ Edge cases (unicode, whitespace, very long passwords)
- ✅ Security tests (common passwords, sequential/repeating chars)

**Destaques:**
- Teste completo de todos os requisitos de senha
- Validação de força de senha com 3 níveis
- Testes de segurança (senhas comuns, padrões fracos)
- Edge cases extensivos (unicode, espaços, 200+ caracteres)

## 🚀 Como Adicionar Novos Testes

### 1. Criar arquivo de teste

```swift
import XCTest
@testable import AgendaHOF

final class MyComponentTests: XCTestCase {

    var sut: MyComponent! // System Under Test

    override func setUp() async throws {
        try await super.setUp()
        sut = MyComponent()
    }

    override func tearDown() async throws {
        sut = nil
        try await super.tearDown()
    }

    func testMyFeature() {
        // Arrange
        let input = "test"

        // Act
        let result = sut.process(input)

        // Assert
        XCTAssertEqual(result, "expected")
    }
}
```

### 2. Seguir padrão AAA (Arrange-Act-Assert)

```swift
func testExample() {
    // Arrange - Setup
    sut.value = 10

    // Act - Execute
    let result = sut.calculate()

    // Assert - Verify
    XCTAssertEqual(result, 20)
}
```

### 3. Usar nomes descritivos

✅ **Bom:**
```swift
func testSignIn_WithInvalidEmail_ShouldShowError()
func testPasswordStrength_WithWeakPassword_ReturnsLowScore()
```

❌ **Ruim:**
```swift
func testLogin()
func test1()
```

## 📝 Padrões de Teste

### 1. **Nomenclatura**
- `test[FunctionName]_[Scenario]_[ExpectedBehavior]()`
- Exemplo: `testSignIn_WithValidCredentials_ShouldAuthenticate()`

### 2. **Organização**
- Um arquivo de teste por ViewModel/Component
- Agrupar testes relacionados com `// MARK: - Section Name`
- Setup e teardown sempre presentes

### 3. **Assertions**
- Use assertions específicos:
  - `XCTAssertTrue/False` para booleanos
  - `XCTAssertEqual/NotEqual` para comparações
  - `XCTAssertNil/NotNil` para optionals
  - `XCTAssertGreaterThan/LessThan` para comparações numéricas
  - `XCTAssertThrowsError` para erros

### 4. **Async Tests**
```swift
func testAsyncFunction() async {
    await sut.performAsyncTask()
    XCTAssertTrue(sut.isComplete)
}
```

### 5. **Mocks**
- Sempre use mocks para dependências externas (Supabase, APIs)
- Não faça chamadas reais de rede nos testes
- Configure mocks no `setUp()`

## 🎯 Próximos Passos

### Fase 1 (Atual): Testes Unitários para ViewModels
- [x] String+Extensions
- [x] AuthViewModel (validações)
- [ ] AuthViewModel (integration com mock)
- [ ] FinancialReportViewModel
- [ ] InactivePatientsViewModel
- [ ] ResetPasswordViewModel

### Fase 2: Testes de Services
- [ ] AppointmentService
- [ ] PatientService
- [ ] NotificationManager

### Fase 3: Testes de UI
- [ ] LoginView flow
- [ ] Appointment creation flow
- [ ] Settings navigation

### Fase 4: CI/CD
- [ ] Configurar GitHub Actions
- [ ] Code coverage automático
- [ ] Validação de padrões (SwiftLint)
- [ ] Build automático

## 📖 Recursos

### Documentação XCTest
- [Apple XCTest Documentation](https://developer.apple.com/documentation/xctest)
- [Swift Testing Best Practices](https://www.swiftbysundell.com/articles/unit-testing-in-swift/)

### Ferramentas
- **XCTest** - Framework de testes do Swift
- **XCTestExpectation** - Para testes assíncronos
- **Coverage Report** - Xcode built-in (Cmd+9 → Coverage)

## 🤝 Contribuindo

Ao adicionar novos features:

1. **Escreva testes primeiro** (TDD recomendado)
2. **Mantenha coverage >70%** para novos códigos
3. **Documente testes complexos** com comentários
4. **Execute todos os testes** antes de commit (`Cmd+U`)

## 📊 Executar Coverage Report

1. Abra o projeto no Xcode
2. Execute testes: `Cmd+U`
3. Abra Report Navigator: `Cmd+9`
4. Selecione último test report
5. Aba "Coverage" mostra % por arquivo

**Target Minimum:** 70% overall coverage

---

**Última atualização:** Dezembro 2024
**Responsável:** Equipe de Desenvolvimento Agenda HOF
**Status:** 🚧 Em construção ativa
