using System;
using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace Swedwise.NodiniteXTArchiveManager.Models
{
    [Table("Metainfs")]
    public class MetainfFileEntity
    {
        // Primary key is the filename stem e.g. "2502_4229bcf0-db68-46e3-947d-536d8afd0b31"
        [Key]
        [MaxLength(200)]
        public string Id { get; set; } = string.Empty;

        // Basic scalar fields from metainf
        public int AckLevel { get; set; }
        public int AckProt { get; set; }
        [MaxLength(200)]
        public string AckProtName { get; set; } = string.Empty;
        public int AckTimeout { get; set; }
        public int ArchiveFlags { get; set; }
        [MaxLength(1000)]
        public string ArchivePath { get; set; } = string.Empty;
        public int CfgVersion { get; set; }
        [MaxLength(800)]
        public string ContractObj { get; set; } = string.Empty;
        [MaxLength(800)]
        public string ContractObjPath { get; set; } = string.Empty;
        public int CreationTime { get; set; }
        public int CurrAckLevel { get; set; }

        // Complex objects stored as JSON for simplicity
        public string? CustomPrivateJson { get; set; }
        public string? CustomPublicJson { get; set; }

        [MaxLength(200)]
        public string DataHashIn { get; set; } = string.Empty;
        [MaxLength(200)]
        public string DataHashOut { get; set; } = string.Empty;
        public int DataSizeIn { get; set; }
        public int DataSizeOut { get; set; }
        [MaxLength(1000)]
        public string FileNameIn { get; set; } = string.Empty;
        [MaxLength(1000)]
        public string FileNameOut { get; set; } = string.Empty;
        public int Flags { get; set; }
        [MaxLength(1000)]
        public string FlagsText { get; set; } = string.Empty;
        [MaxLength(1000)]
        public string FolderIn { get; set; } = string.Empty;

        [MaxLength(800)]
        public string FromObj { get; set; } = string.Empty;
        [MaxLength(800)]
        public string FromObjPath { get; set; } = string.Empty;
        [MaxLength(500)]
        public string FromParty { get; set; } = string.Empty;
        [MaxLength(500)]
        public string FromPartyPath { get; set; } = string.Empty;
        public int FromProt { get; set; }
        [MaxLength(200)]
        public string FromProtName { get; set; } = string.Empty;

        public int InternalId { get; set; }
        public int KnownVersion { get; set; }
        public int LastState { get; set; }

        // LocalRefs and Logs as JSON
        public string? LocalRefsJson { get; set; }
        public string? LogsJson { get; set; }

        public int MsgId { get; set; }
        [MaxLength(2000)]
        public string MsgInfo { get; set; } = string.Empty;
        public int MsgType { get; set; }
        [MaxLength(200)]
        public string MsgUuid { get; set; } = string.Empty;
        public int Owner { get; set; }

        public string? ParseInfoInJson { get; set; }
        public string? ParseInfoOutJson { get; set; }

        public int Priority { get; set; }
        public int ProcDuration { get; set; }
        public int SeqIdIn { get; set; }
        public int SeqIdOut { get; set; }
        public int SeqNoIn { get; set; }
        public int SeqNoOut { get; set; }
        public int SeqTypeIn { get; set; }
        public int SeqTypeOut { get; set; }
        [MaxLength(200)]
        public string SeqUuidIn { get; set; } = string.Empty;
        [MaxLength(200)]
        public string SeqUuidOut { get; set; } = string.Empty;

        public int State { get; set; }
        [MaxLength(200)]
        public string StateName { get; set; } = string.Empty;
        public int SyncFlags { get; set; }
        public bool SyncReply { get; set; }

        [MaxLength(800)]
        public string ToObj { get; set; } = string.Empty;
        [MaxLength(800)]
        public string ToObjPath { get; set; } = string.Empty;
        [MaxLength(500)]
        public string ToParty { get; set; } = string.Empty;
        [MaxLength(500)]
        public string ToPartyPath { get; set; } = string.Empty;
        public int ToProt { get; set; }
        [MaxLength(200)]
        public string ToProtName { get; set; } = string.Empty;
        public int Version { get; set; }
        [MaxLength(200)]
        public string WfInst { get; set; } = string.Empty;

        // Derived object ids (regex extraction) - stored for convenience
        [MaxLength(200)]
        public string ContractObjId { get; set; } = string.Empty;
        [MaxLength(200)]
        public string ToObjId { get; set; } = string.Empty;
        [MaxLength(200)]
        public string FromObjId { get; set; } = string.Empty;

        // Keep original JSON and timestamp
        public string RawJson { get; set; } = string.Empty;
        public DateTime CreatedAt { get; set; } = DateTime.UtcNow;

        // New datetime derived from CreationTime; mapped to SQL column 'CreationTime_Dt' of type DATETIME
        [Column("CreationTime_Dt", TypeName = "datetime")]
        public DateTime CreationTimeDt { get; set; }
    }
}
