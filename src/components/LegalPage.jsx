const LEGAL_CONTENT = {
  terms: {
    title: 'Terms of Service',
    intro:
      'These draft terms describe the basic rules for using Recess during the MVP. They should be reviewed and approved by the project owner before production release.',
    sections: [
      {
        heading: 'Using Recess',
        body: 'Recess is a social connection app for verified university students and professionals. You must provide accurate information, keep your account secure, and use the service respectfully.',
      },
      {
        heading: 'Acceptable behaviour',
        body: 'Do not harass, threaten, impersonate, scam, or share harmful or unlawful content. Do not use Recess to arrange unsafe activity or to collect another person\'s information without permission.',
      },
      {
        heading: 'Content and visibility',
        body: 'You are responsible for the status updates, event information, and other content you post. Location sharing is optional, and you should only share information you are comfortable making visible to other verified members.',
      },
      {
        heading: 'Account suspension',
        body: 'We may restrict or suspend accounts that breach these terms, create a safety risk, or misuse the service. You can report inappropriate content or behaviour to the project team.',
      },
      {
        heading: 'Changes and contact',
        body: 'The MVP may change as the project develops. We will update this page when material changes are made. For questions, contact the Recess project team through the approved university or organisation channel.',
      },
    ],
  },
  privacy: {
    title: 'Privacy Policy',
    intro:
      'This draft explains the information Recess uses during the MVP. It should be reviewed against the applicable university, workplace, and Australian privacy requirements before production release.',
    sections: [
      {
        heading: 'Information we collect',
        body: 'We may collect your name, verified university or organisation email address, account status, profile details, status updates, event activity, and the location information you choose to share.',
      },
      {
        heading: 'How we use information',
        body: 'We use this information to authenticate accounts, verify that members belong to an approved organisation, show nearby activity when you choose to share it, provide app features, and protect the community.',
      },
      {
        heading: 'Sharing and visibility',
        body: 'Your profile and posts may be visible to other verified members within the relevant university or organisation scope. We do not sell personal information. Location sharing should be treated as optional and time-limited whenever possible.',
      },
      {
        heading: 'Security and retention',
        body: 'We use reasonable technical and organisational safeguards for account and location data. Information is retained only for as long as needed for the MVP, safety, legal, or operational purposes, subject to project and platform policies.',
      },
      {
        heading: 'Your choices',
        body: 'You can choose whether to share your current location, update your profile information, and request help with account or privacy concerns through the Recess project team.',
      },
    ],
  },
};

export default function LegalPage({ type, onBack }) {
  const content = LEGAL_CONTENT[type] ?? LEGAL_CONTENT.terms;

  return (
    <main className="min-h-screen bg-orange-50 px-4 py-8 font-sans">
      <article className="mx-auto max-w-3xl rounded-2xl border border-neutral-100 bg-white p-6 shadow-sm md:p-10">
        <div className="mb-8 flex items-center justify-between gap-4">
          <button
            type="button"
            onClick={onBack}
            className="text-xs font-medium text-neutral-500 hover:text-neutral-800"
          >
            ← Back
          </button>
          <span className="text-xs font-semibold uppercase tracking-wider text-orange-600">
            Recess
          </span>
        </div>

        <p className="mb-2 text-xs font-semibold uppercase tracking-widest text-neutral-400">
          MVP draft · Last updated 17 September 2026
        </p>
        <h1 className="text-3xl font-bold text-neutral-900">{content.title}</h1>
        <p className="mt-4 text-sm leading-6 text-neutral-600">{content.intro}</p>

        <div className="mt-8 space-y-6">
          {content.sections.map((section) => (
            <section key={section.heading}>
              <h2 className="text-base font-semibold text-neutral-900">{section.heading}</h2>
              <p className="mt-2 text-sm leading-6 text-neutral-600">{section.body}</p>
            </section>
          ))}
        </div>
      </article>
    </main>
  );
}
