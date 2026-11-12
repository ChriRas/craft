# Symfony — Twig, Forms and Validation

Twig 3.30 (`symfony/twig-bundle`), the Form component and the Validator component, as wired in Symfony 8.1 and 7.4. Install
with `composer require symfony/twig-pack symfony/form symfony/validator` (Flex normally adds them with the first feature
that needs them).

## Templates

- **Layout** — three levels for a medium or large app: `templates/base.html.twig` (the shell), `templates/layout.html.twig`
  (the content structure), one template per page that `{% extends %}` it and fills `{% block %}`s. Template names and
  variables are lowercase `snake_case` (`invoice/edit_form.html.twig`, `user_profile`); a partial is prefixed with an
  underscore (`_invoice_row.html.twig`) and pulled in with the `include()` function.
- **No logic** — a template presents what the controller or a Twig extension prepared: loops, `if`, formatting. No queries,
  no business rules, no `app.request` poking for decisions the controller should make. Pass only what the page needs, as
  scalars, DTOs or entities read-only.
- **Escaping** — output is escaped automatically; `|raw` is for a value you built and trust (sanitized HTML, a rendered
  child), never for user input. Mark a trusted HTML value object safe with the `twig.safe_class` tag (8.1) rather than `|raw`
  everywhere.
- **Links and assets** — `path('invoice_show', {id: invoice.id})` for routes, `asset('images/logo.png')` for
  public files; never hand-built URLs. The recipe turns on `strict_variables` in `when@test`, so a typo in a variable
  name fails a test instead of printing nothing; keep it on.
- **Security in templates** — `{% if is_granted('INVOICE_EDIT', invoice) %}` hides a link; the controller or voter still
  enforces it. `app.user` is the current user (`null` when anonymous).
- **Reuse** — Twig components are the documented way to reuse a fragment with its own logic (a component class plus a
  template) when an `include` is not enough; an inline `{% macro %}` for tiny presentation helpers.
- **Fragments and caching** — `render(controller(...))` runs a separate sub-request for the fragment; prefer an `include`
  with data passed in, and cache with the HTTP cache or `CacheInterface` rather than in the template.
- **Translations** — the `trans` filter on a key (`'invoice.paid'|trans`) with keys that name the purpose; plural and parameters in the message.

### Twig extensions

An extension adds filters, functions and tests; with attributes it is a plain service class:

```php
final class MoneyExtension
{
    #[AsTwigFilter('money')]
    public function format(Money $money, string $locale = 'en'): string
    {
        $formatter = new \NumberFormatter($locale, \NumberFormatter::CURRENCY);

        return $formatter->formatCurrency($money->amount / 100, $money->currency);
    }

    #[AsTwigFunction('invoice_status_class')]
    public function statusClass(InvoiceStatus $status): string { /* ... */ }
}
```

- `#[AsTwigFilter]` / `#[AsTwigFunction]` (namespace `Twig\Attribute`) are what the 8.1 and 7.4 docs show; the older
  `AbstractExtension` with `getFilters()` still works and is what an older project has.
- An extension is a stateless service; one that needs a heavy dependency should be lazy-loaded (a `RuntimeExtensionInterface`
  class) so every page does not build it. `php bin/console debug:twig` lists what is registered.
- `php bin/console lint:twig templates/` in CI catches syntax errors.

## Forms

A form is a typed translation between a request and an object. Define each form as a class and let one action render and
process it:

```php
final class InvoiceType extends AbstractType
{
    public function buildForm(FormBuilderInterface $builder, array $options): void
    {
        $builder
            ->add('number', TextType::class)
            ->add('issuedAt', DateType::class, ['widget' => 'single_text', 'input' => 'datetime_immutable'])
            ->add('status', EnumType::class, ['class' => InvoiceStatus::class]);
    }

    public function configureOptions(OptionsResolver $resolver): void
    {
        $resolver->setDefaults(['data_class' => InvoiceData::class]);
    }
}
```

```php
#[Route('/invoices/new', name: 'invoice_new', methods: ['GET', 'POST'])]
public function new(Request $request, InvoiceService $invoices): Response
{
    $form = $this->createForm(InvoiceType::class, new InvoiceData());
    $form->handleRequest($request);

    if ($form->isSubmitted() && $form->isValid()) {
        $invoice = $invoices->create($form->getData());

        return $this->redirectToRoute('invoice_show', ['id' => $invoice->getId()]);
    }

    return $this->render('invoice/new.html.twig', ['form' => $form]);
}
```

- **Types in classes**, not built in the controller; `data_class` set explicitly. Buttons are added in the template
  (`form_row(form.save)` or a plain `<button>`), so one type serves create and edit; a form with several submit
  buttons defines them in the type so the controller can ask which was clicked.
- **Bind to a DTO or command** rather than a Doctrine entity when the form is not a 1:1 edit of the entity; the controller
  hands the validated DTO to a service. For an edit form bound to an entity, the form updates the entity in place and the
  service flushes.
- **Process and render in one action** (GET renders, POST processes) with the redirect after success (post/redirect/get).
  Passing the `FormInterface` itself to `render()` (not `$form->createView()`) makes an invalid submit answer **422**
  automatically, which UX Turbo and other clients need.
- **Validation** lives on the underlying object (`#[Assert\...]`), not on form fields, so a form, an API and a command all
  reuse it. A form field only sets presentation: type, label, options, `required`, `mapped`, `help`.
- **Choices** — `EnumType` for backed enums, `EntityType` (`class`, `choice_label`, a `query_builder` closure) for entities,
  `ChoiceType` for fixed lists; `CollectionType` with `allow_add` / `allow_delete` for repeated rows, validated with
  `#[Assert\Valid]` on the collection.
- **Files** — `FileType` with `#[Assert\File]` / `#[Assert\Image]` constraints; move the upload in a service, name the stored file
  yourself, never trust the client name or MIME type.
- **Extra fields** are rejected unless `allow_extra_fields` is set; `mapped: false` for a field that must not touch the
  object (a "confirm" checkbox). Multi-step forms: FormFlow (`AbstractFlowType`) exists since 7.4; 8.1 adds the `createFormFlowBuilder()` shortcut.
- **Rendering** — `form(form)` for a quick page, otherwise `form_start()`, one `form_row()` per field and `form_end()`
  (`form_end` also calls `form_rest()`, which renders the CSRF token and any field you left out). Pick a theme once in
  `twig.form_themes` (for example `bootstrap_5_layout.html.twig`); override a block in a form theme, not by copying markup.
- **CSRF** — on by default for every form; keep it on. Disable it only on a stateless API form (`csrf_protection: false`)
  and say why.
- **Form tests** — `TypeTestCase` (`Symfony\Component\Form\Test`) for a form type in isolation;
  `WebTestCase::submitForm()` for the page (`test-patterns.md`).

## Validation

- Constraints are attributes on the class: `#[Assert\NotBlank]`, `#[Assert\Length(max: 255)]`, `#[Assert\Email]`,
  `#[Assert\Range]`, `#[Assert\Choice]`, `#[Assert\Valid]` (validate a nested object or each item of a collection),
  `#[Assert\Callback]` for a rule across fields, `UniqueEntity` for a Doctrine uniqueness check. Put the same rule in the
  database (a unique index, a `NOT NULL`): the validator is the friendly message, the constraint the guarantee.
- **Validation groups** — `groups: ['create']` on a constraint, `validation_groups` on the form or on
  `#[MapRequestPayload]`, for rules that differ between create and edit.
- **A custom constraint** is a `Constraint` attribute class plus a `ConstraintValidator` service (autoconfigured);
  `validate()` adds a violation with `buildViolation()` and returns nothing. A validator that needs the database takes the
  repository in its constructor.
- **Where it runs** — forms validate on `handleRequest()`; `#[MapRequestPayload]` / `#[MapQueryString]` validate while
  mapping (a failure answers 422 / 404 by default); in a service call `ValidatorInterface::validate($object)` and handle
  the `ConstraintViolationList`. Validate at the boundary once, then pass trusted objects inward.
- **Messages** — a violation message names the problem for a user, not the rule; translate it with the Translation
  component like any other text.
