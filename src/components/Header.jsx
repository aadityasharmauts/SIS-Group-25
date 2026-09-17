export default function Header({ page, onBack, showEventForm, onToggle, onNavigate }) {
    return (
      <header className="bg-white border border-neutral-100 rounded-2xl px-4 py-3 flex justify-between items-center sticky top-4 z-10 mb-5 shadow-sm">
        <div className="flex items-center gap-2.5">
          {page === 'event' || page === 'profile' ? (
            <button
              type="button"
              onClick={onBack}
              className="text-sm font-semibold text-neutral-500 hover:text-neutral-800 transition-colors"
            >
              ← Back
            </button>
          ) : (
            <>
              <div className="w-8 h-8 bg-orange-100 rounded-lg flex items-center justify-center border border-orange-200">
                <span className="text-orange-700 font-bold text-sm">R</span>
              </div>
              <div>
                <p className="text-sm font-bold tracking-tight text-neutral-950 leading-none">Recess</p>
                <p className="text-[11px] text-neutral-400 mt-0.5">Work, study, connect</p>
              </div>
            </>
          )}
        </div>
        <div className="flex items-center gap-2">
          {page === 'feed' && (
            <>
            <button
                onClick={() => onNavigate('profile')}
                className="text-xs bg-neutral-100 hover:bg-neutral-200 text-neutral-700 font-semibold px-3 py-2 rounded-xl transition-colors"
              >
                Profile
              </button>
              
              <div className="flex items-center gap-1.5 text-xs text-neutral-500 bg-white border border-neutral-100 rounded-full px-3 py-1">
                <span className="relative flex h-1.5 w-1.5">
                  <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-orange-400 opacity-75" />
                  <span className="relative inline-flex rounded-full h-1.5 w-1.5 bg-orange-500" />
                </span>
                UTS Campus
              </div>
              <button
                onClick={onToggle}
                className="text-xs bg-orange-600 hover:bg-orange-700 text-white font-semibold px-3.5 py-2 rounded-xl transition-colors"
              >
                {showEventForm ? '✕ Cancel' : '+ Host event'}
              </button>
            </>
          )}
        </div>
      </header>
    );
  }