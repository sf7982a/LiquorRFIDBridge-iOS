type Props = {
  isLoading: boolean;
  canNext: boolean;
  onNext: () => void;
};

export function Pagination({ isLoading, canNext, onNext }: Props) {
  return (
    <div className="pagination">
      <button className="btn" onClick={onNext} disabled={isLoading || !canNext}>
        {isLoading ? "Loading…" : "Next Page"}
      </button>
    </div>
  );
}


