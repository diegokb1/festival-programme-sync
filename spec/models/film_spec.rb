require "rails_helper"

RSpec.describe Film do
  describe "associations" do
    it "destroys its screenings when destroyed" do
      film      = create(:film)
      screening = create(:screening, film: film)

      expect { film.destroy }.to change(Screening, :count).by(-1)
      expect { screening.reload }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "validations" do
    it "is valid with the factory defaults" do
      expect(build(:film)).to be_valid
    end

    it "requires an external_id" do
      film = build(:film, external_id: nil)

      expect(film).not_to be_valid
      expect(film.errors[:external_id]).to include("can't be blank")
    end

    it "requires external_id to be unique" do
      create(:film, external_id: "FILM-001")
      duplicate = build(:film, external_id: "FILM-001")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:external_id]).to include("has already been taken")
    end

    it "requires a title" do
      film = build(:film, title: nil)

      expect(film).not_to be_valid
      expect(film.errors[:title]).to include("can't be blank")
    end
  end
end
