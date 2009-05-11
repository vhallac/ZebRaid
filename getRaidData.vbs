
Function ReadPage(URL)
    PageText = ""

    Set WinHttpReq = CreateObject("WinHttp.WinHttpRequest.5.1")
    WinHttpReq.Open "GET", URL, False
    WinHttpReq.Send

    If (WinHttpReq.Status = 200) Then
        PageText = WinHttpReq.ResponseText
    End If

    ReadPage = PageText
End Function

Function ScrapeTable(Cells, message)
    
    scraped = ""
  
    For classrow = 0 To Cells.Length - 1
        attendName = ""
        attendNote = ""
        attendRoll = ""
        Set Members = Cells(classrow).Children
        Set member = Members(0).Rows(1).Cells(0)
        For i = 0 To member.Children.Length - 1
            Set cmember = member.Children(i)
            attendName = Trim(cmember.Rows(1).Cells(1).innertext)
            attendNote = Trim(cmember.Rows(1).Cells(0).innerHTML)
            attendRoll = Trim(cmember.Rows(1).Cells(2).innerHTML)
                        
            If attendNote <> "" Then
                bul = InStr(attendNote, "note.png")
                attendNote = Mid(attendNote, bul + 21)
                bul = InStr(attendNote, "<td>")
                attendNote = Trim(Mid(attendNote, bul + 5))
                bul = InStr(attendNote, "</td>")
                attendNote = Trim(Left(attendNote, bul - 1))
            End If
                
            If attendRoll <> "" Then
                bul = InStr(attendRoll, "roll.png")
                attendRoll = Mid(attendRoll, bul + 21)
                bul = InStr(attendRoll, "<td>")
                attendRoll = Trim(Mid(attendRoll, bul + 5))
                bul = InStr(attendRoll, "</td>")
                attendRoll = Trim(Left(attendRoll, bul - 1))
            End If
            scraped = scraped & "    """
            scraped = scraped & attendName
            scraped = scraped & ":" & message & ":" & attendRoll
            scraped = scraped & ":" & attendNote & ""","
            scraped = scraped & vbCrLf
        Next
'        For i = 0 To Members.Length - 1
'            Set member = Members(i).Rows(1).Cells
'            scraped = scraped & "    """
'            scraped = scraped & Trim(member(1).Children(0).innerText)
'            scraped = scraped & ":" & message & ":" & Trim(member(3).innerText)
'            ' Can't get member(0).children(0) to work.
'            note = member(0).innerHTML
'            If Len(note) > 0 Then
'                note = Replace(note, "<A onmouseover=""overlib('", "")
'                note = Left(note, InStr(note, "',") - 1)
'            End If
'            scraped = scraped & ":" & Trim(note) & ""","
'            scraped = scraped & vbCrLf
'        Next
    Next
    ScrapeTable = scraped
End Function

Function ScrapeData(PageText)
    locConfirTbl = -1
    locSignedTbl = -1
    locNotsurTbl = -1
    locUnsignTbl = -1
    tblTitle = ""
    
    Set oDoc = CreateObject("HtmlFile")
    oDoc.Open
    oDoc.write PageText
    oDoc.Close

    scraped = ""
    
    For mx = 0 To oDoc.getElementsByTagName("table").Length - 1
        tblTitle = Trim(oDoc.getElementsByTagName("table")(mx).Rows(0).innertext)
        
        If Left(tblTitle, 11) = "Confirmed (" Then locConfirTbl = mx + 1
        If Left(tblTitle, 8) = "Signed (" Then locSignedTbl = mx + 1
        If Left(tblTitle, 10) = "Unsigned (" Then locUnsignTbl = mx + 1
        If Left(tblTitle, 10) = "Not Sure (" Then locNotsurTbl = mx + 1
    Next
    ' Get the confirmed list as signed
    'Set signedCells = oDoc.getElementsByTagName("table")(5).Rows(2).Cells
    Set signedCells = oDoc.getElementsByTagName("table")(locConfirTbl).Rows(0).Cells
    scraped = scraped & ScrapeTable(signedCells, "signed")

    ' Get the signed list
    Set signedCells = oDoc.getElementsByTagName("table")(locSignedTbl).Rows(0).Cells
    scraped = scraped & ScrapeTable(signedCells, "signed")

    ' Get the unsigned list
    Set signedCells = oDoc.getElementsByTagName("table")(locUnsignTbl).Rows(0).Cells
    scraped = scraped & ScrapeTable(signedCells, "unsigned")

    ' Get the unsure list
    Set signedCells = oDoc.getElementsByTagName("table")(locNotsurTbl).Rows(0).Cells
    scraped = scraped & ScrapeTable(signedCells, "unsure")

    ScrapeData = scraped
End Function

RaidId = InputBox("What is the raid ID? ")
raidPage = ReadPage("http://www.zebraguild.com/dkp40/plugins/raidplan/viewraid.php?r=" & RaidId)

' Parse the planned tables, and prepare output (raidData variable holds it)
RaidId = RaidId & "_" & FormatDateTime(Now(), vbShortDate)
raidData = "ZebRaid.RaidID = """ & RaidId & """" & vbCrLf
raidData = raidData & "ZebRaid.Signups = {" & vbCrLf
raidData = raidData & ScrapeData(raidPage)
raidData = raidData & "};" & vbCrLf

' Report the results
Const outFileName = "signups.lua"

With CreateObject("Scripting.FileSystemObject")
    If .FileExists(outFileName) Then
        .DeleteFile outFileName
    End If
End With

' Write to file in UTF-8 format. WoW wants it.
With CreateObject("adodb.stream")
        .Type = 2
        .Open
        .Charset = "utf-8"
        .WriteText raidData
        .savetoFile outFileName
End With

MsgBox ("Raid data written to " & outFileName & " successfully")




