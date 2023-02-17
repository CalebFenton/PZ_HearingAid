require "Items/Distributions";
require "Items/ProceduralDistributions";

local IneffecientHearingAidSpawns = {
    CrateElectronics = 1,
    ClosetShelfGeneric = 1,
    ClothingStoresEyewear = 1,
    OfficeDeskHome = 3,
    OfficeDesk = 2,
    DeskGeneric = 1,
    ElectronicStoreMisc = 1,
};

local EffecientHearingAidSpawns = {
    CrateElectronics = 0.05,
    ClosetShelfGeneric = 0.05,
    ClothingStoresEyewear = 0.05,
    OfficeDeskHome = 0.15,
    OfficeDesk = 0.1,
    DeskGeneric = 0.05,
    ElectronicStoreMisc = 0.05,
};

for distributionName, rate in pairs(IneffecientHearingAidSpawns) do
    local distribution = ProceduralDistributions.list[tostring(distributionName)];
    table.insert(distribution.items, "hearing_aid.InefficientHearingAid");
    table.insert(distribution.items, rate);
end

for distributionName, rate in pairs(EffecientHearingAidSpawns) do
    local distribution = ProceduralDistributions.list[tostring(distributionName)];
    table.insert(distribution.items, "hearing_aid.EfficientHearingAid");
    table.insert(distribution.items, rate);
end

table.insert(SuburbsDistributions["all"]["inventoryfemale"].items, "hearing_aid.InefficientHearingAid");
table.insert(SuburbsDistributions["all"]["inventoryfemale"].items, 0.03);
table.insert(SuburbsDistributions["all"]["inventorymale"].items, "hearing_aid.InefficientHearingAid");
table.insert(SuburbsDistributions["all"]["inventorymale"].items, 0.03);

table.insert(SuburbsDistributions["all"]["inventoryfemale"], "hearing_aid.BrokenHearingAid");
table.insert(SuburbsDistributions["all"]["inventoryfemale"], 0.1);
table.insert(SuburbsDistributions["all"]["inventorymale"], "hearing_aid.BrokenHearingAid");
table.insert(SuburbsDistributions["all"]["inventorymale"], 0.1);
