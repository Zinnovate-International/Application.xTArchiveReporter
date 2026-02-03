using System;

namespace Swedwise.NodiniteXTArchiveManager.Models;

public class MetainfAggregationRequest
{
    public string? FromObjPath { get; set; }
    public string? ContractObjPath { get; set; }
    public string? ToObjPath { get; set; }
    public DateTime? StartDate { get; set; }
    public DateTime? EndDate { get; set; }
}

public class MetainfAggregationResult
{
    public string FromObjPath { get; set; } = string.Empty;
    public string ContractObjPath { get; set; } = string.Empty;
    public string ToObjPath { get; set; } = string.Empty;
    public int IncidentCount { get; set; }
}
