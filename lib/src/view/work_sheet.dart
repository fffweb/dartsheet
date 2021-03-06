part of dartsheet.view;

class WorkSheet extends VGroup {
  
  @event Stream<FrameworkEvent<List<Cell>>> onSelectedCellsChanged;
  @event Stream<FrameworkEvent<List<Cell>>> onSelectionStart;
  @event Stream<FrameworkEvent<List<Cell>>> onSelectionEnd;
  @event Stream<FrameworkEvent<Formula>> onScriptValidationChanged;
  
  //---------------------------------
  //
  // Protected properties
  //
  //---------------------------------
  
  final int initRows;
  final int initCols;
  
  Cell lastEditedCell;
  
  operations.OperationsManager _operationsManager;
  
  //---------------------------------
  //
  // Public properties
  //
  //---------------------------------
  
  ListRenderer columnList;
  Spreadsheet spreadsheet;
  HandleBar hHandleBar, vHandleBar;
  
  //---------------------------------
  // selectedCells
  //---------------------------------
  
  List<Cell> _selectedCells, _lockedCells;
  
  List<Cell> get selectedCells => _selectedCells;
  
  //---------------------------------
  //
  // Constructor
  //
  //---------------------------------
  
  WorkSheet(this.initRows, this.initCols) : super() {
    _operationsManager = new operations.OperationsManager(this);
    
    context['__registerNewRxSubscription'] = _registerNewRxSubscription;
    context["Select"] = _cellStreamHandler;
  }
  
  //---------------------------------
  //
  // Public methods
  //
  //---------------------------------
  
  @override
  void createChildren() {
    super.createChildren();
    
    final HGroup gridGroup = new HGroup(gap: 0)
      ..className = 'workbook'
      ..percentWidth = 100.0
      ..percentHeight = 100.0;
    
    final VGroup columnListGroup = new VGroup(gap: 0)
      ..width = 30
      ..percentHeight = 100.0;
    
    final Spacer spacer = new Spacer()
      ..percentWidth = 100.0
      ..height = 23;
    
    columnList = new ListRenderer()
      ..rowHeight = 23
      ..percentWidth = 100.0
      ..percentHeight = 100.0
      ..autoManageScrollBars = false
      ..horizontalScrollPolicy = ScrollPolicy.NONE
      ..verticalScrollPolicy = ScrollPolicy.NONE
      ..lockIndex = 2
      ..itemRendererFactory = new ItemRendererFactory<RowItemRenderer<Row<Cell>>>(
          constructorMethod: RowItemRenderer.construct, 
          className: 'row-item-renderer'
      )
      ..onWidthChanged.listen((_) => invalidateLayout());
    
    columnListGroup.addComponent(spacer);
    columnListGroup.addComponent(columnList);
    
    spreadsheet = new Spreadsheet()
      ..cssClasses = const <String>[]
      ..allowHeaderColumnSorting = false
      ..percentWidth = 100.0
      ..percentHeight = 100.0
      ..allowMultipleSelection = true
      ..headerHeight = 24
      ..rowHeight = columnList.rowHeight
      ..columnSpacing = 0
      ..rowSpacing = 0
      ..autoScrollOnDataChange = true
      ..columns = _createGridColumns()
      ..useEvenOdd = false
      ..rowLockIndex = 2
      ..columnLockIndex = 2
      ..onListScrollPositionChanged.listen(_updateOverlay)
      ..onHeightChanged.listen(_updateOverlay)
      ..onRendererAdded.listen(_handleNewRowRenderer)
      ..onRowLockIndexChanged.listen((FrameworkEvent<int> event) => columnList.lockIndex = event.relatedObject)
      ..onHeaderResize.listen((_) => invalidateLayout());
    
    hHandleBar = new HandleBar()
      ..height = 4
      ..orientation = 'horizontal'
      ..includeInLayout = false
      ..onDragStart.listen(_drag_startHandler)
      ..onDrag.listen(_hHandleBar_dragHandler)
      ..onDragEnd.listen(_hHandleBar_dragEndHandler);
    
    vHandleBar = new HandleBar()
      ..width = 4
      ..orientation = 'vertical'
      ..includeInLayout = false
      ..onDragStart.listen(_drag_startHandler)
      ..onDrag.listen(_vHandleBar_dragHandler)
      ..onDragEnd.listen(_vHandleBar_dragEndHandler);
    
    gridGroup.addComponent(columnListGroup);
    gridGroup.addComponent(spreadsheet);
    gridGroup.addComponent(hHandleBar);
    gridGroup.addComponent(vHandleBar);
    
    addComponent(gridGroup);
    
    spreadsheet.dataProvider = new ObservableList<Row<Cell>>.from(_createRows(0));
    
    _updateOverlay();
  }
  
  Future invalidateFormula(Formula formula) async {
    await formula.appliesTo.clearSiblingSubscriptions();
    
    formula.isValid = true;
    
    final JsFunctionBody jsf = formula.getJavaScriptFunctionBody(spreadsheet.dataProvider, formula.appliesTo.siblingSubscriptions);
    
    if (formula.appliesTo.scriptElement != null) formula.appliesTo.scriptElement.remove();
    
    formula.cancelSubscription();
    
    try {
      final String es5body = context['babel'].callMethod('transform', [jsf.value])['code'].replaceAll('.subscribe(', '.__subscribe("${formula.appliesTo.id}", ');
      
      formula.appliesTo.scriptElement = new ScriptElement()..innerHtml = es5body;
      
      document.head.append(formula.appliesTo.scriptElement);
      
      context['onvalue_${formula.appliesTo.id}'] = (dynamic yieldValue) {
        formula.appliesTo.value = yieldValue.toString();
        
        return yieldValue;
      };
      
      context['onvaluedown_${formula.appliesTo.id}'] = (dynamic yieldValue) {
        for (int i=formula.appliesTo.rowIndex, len=spreadsheet.dataProvider.length; i<len; i++) {
          Row<Cell<String>> row = spreadsheet.dataProvider[i];
          Cell<String> cell = row.cells[formula.appliesTo.colIndex];
          
          if (cell.value == null || cell.value.isEmpty) {
            cell.value = yieldValue.toString();
            
            return yieldValue;
          }
        }
        
        return yieldValue;
      };
      
      context['oncss_${formula.appliesTo.id}'] = (JsObject yieldValue) {
        formula.appliesTo.style = yieldValue;
        
        return yieldValue;
      };
      
      formula.isValid = context.callMethod('__${formula.appliesTo.id}', []);
      
      //print('ES6 successful: ' + es5body);
    } catch (error) {
      //print('Failed to convert to ES6: ' + jsf.value);
      print('Failed to convert to ES6: ' + error);
      
      formula.appliesTo.value = null;
      
      formula.isValid = false;
    }
    
    notify('scriptValidationChanged', formula);
  }
  
  @override
  void updateLayout() {
    super.updateLayout();
    
    if (hHandleBar != null) {
      hHandleBar.width = columnList.width + spreadsheet.width - 15;
      hHandleBar.paddingLeft = 0;
      hHandleBar.indicatorSize = columnList.width;
      hHandleBar.y = hHandleBar.paddingTop = spreadsheet.headerHeight + spreadsheet.rowLockIndex * spreadsheet.rowHeight - hHandleBar.height ~/ 2;
    }
    
    if (vHandleBar != null) {
      vHandleBar.height = spreadsheet.height - 15;
      vHandleBar.indicatorSize = spreadsheet.headerHeight;
      vHandleBar.paddingTop = 0;
      
      int dx = - vHandleBar.width ~/ 2;
      
      for (int i=0; i<spreadsheet.columnLockIndex; i++)
        dx += spreadsheet.columns[i].width;
      
      vHandleBar.x = vHandleBar.paddingLeft = columnList.x + columnList.width + dx;
    }
  }
  
  void focusCellSibling(CellItemRenderer<Cell> currentFocus, int rowOffset, int colOffset) {
    final Cell cell = currentFocus.data;
    final Cell nextCell = getCell(cell.rowIndex + rowOffset, cell.colIndex + colOffset);
    
    if (nextCell != null) for (int i=0, len=spreadsheet.list.itemRenderers.length; i<len; i++) {
      DataGridItemRenderer<Row<Cell>> IR = spreadsheet.list.itemRenderers[i];
      
      for (int j=0, len2=IR.data.cells.length; j<len2; j++) {
        Cell C = IR.data.cells[j];
        
        if (C == nextCell) {
          CellItemRenderer<Cell> targetCellIR = IR.itemRendererInstances[j] as CellItemRenderer<Cell>;
          
          currentFocus.textArea.control.blur();
          targetCellIR.textArea.control.focus();
          
          selectCell(targetCellIR, isSelectionStart: false);
          
          return;
        }
      }
    }
  }
  
  void saveToFile() {
    final String json = save();
    final Blob blob = new Blob(<String>[json], 'text/plain', 'native');
    final String url = Url.createObjectUrlFromBlob(blob);
    final AnchorElement link = new AnchorElement()
      ..href = url
      ..download = 'rxsheet.json';
    
    link.click();
  }
  
  void loadFromFile() {
    InputElement dialog = new InputElement(type: 'file');
    
    dialog.onChange.listen((Event event) {
      final File file = dialog.files.first;
      final FileReader reader = new FileReader();
      
      reader.readAsText(file);
      
      reader.onLoadEnd.listen((ProgressEvent E) {
        load(reader.result);
      });
      
      event.preventDefault();
    });
    
    dialog.click();
  }
  
  String save() {
    final ObservableList<Row<Cell>> dataProvider = spreadsheet.dataProvider as ObservableList<Row<Cell>>;
    final List<Map<String, dynamic>> list = <Map<String, dynamic>>[];
    
    dataProvider.forEach((Row<Cell> row) {
      row.cells.forEach((Cell cell) {
        if (!cell.isEmpty()) list.add(cell.mappify());
      });
    });
    
    return JSON.encode(list);
  }
  
  void load(String data) {
    final List<Map<String, dynamic>> list = JSON.decode(data);
    
    list.forEach((Map<String, dynamic> entry) => 
        getCellById(entry['id'])
        ..value = entry['value']
        ..formula.originator = getCellById(entry['originator'])
        ..formula.body = entry['formula']
    );
  }
  
  void selectCell(CellItemRenderer<Cell> target, {bool isSelectionStart: false}) {
    StreamSubscription mouseUpSubscription;
    
    if (_selectionStartCell != null) _selectionStartCell.focused = false;
    
    _cleanCurrentSelection();
    
    _selectionStartCell = target.data;
    
    _selectionStartCell.focused = true;
    
    if (isSelectionStart) {
      _isInSelectionMode = true;
      
      mouseUpSubscription = document.onMouseUp.listen((MouseEvent event) {
        _isInSelectionMode = false;
        _isInLockedSelectionMode = false;
        
        _lockedCells = null;
        
        mouseUpSubscription.cancel();
        
        notify('selectionEnd');
      });
    }
    
    _updateCurrentSelection(_selectionStartCell, _selectionStartCell);
  }
  
  Cell getCell(int row, int col) {
    if (row >= 0 && row < spreadsheet.dataProvider.length && col >= 0 && col < spreadsheet.columns.length)
      return (spreadsheet.dataProvider as ObservableList<Row<Cell>>)[row].cells[col];
    
    return null;
  }
  
  Cell getCellById(String cellId) {
    for (int i=0, len=spreadsheet.dataProvider.length; i<len; i++) {
      Row<Cell> row = spreadsheet.dataProvider[i];
      
      for (int j=0, len2=row.cells.length; j<len2; j++) {
        Cell cell = row.cells[j];
        
        if (cell.id == cellId) return cell;
      }
    }
    
    return null;
  }
  
  //---------------------------------
  //
  // Protected methods
  //
  //---------------------------------
  
  Iterable<Row<Cell>> _createRows(int startRowIndex) sync* {
    yield* new List<Row<Cell>>.generate(initRows, (int rowIndex) => _createRow(startRowIndex + rowIndex));
  }
  
  ObservableList<DataGridColumn> _createGridColumns() {
    final ObservableList<DataGridColumn> list = new ObservableList<DataGridColumn>.from(
      new List<DataGridColumn>.generate(initCols, (int i) {
        String id;
        
        if (i >= 26 ) id = new String.fromCharCodes(<int>[64 + i ~/ 26, 65 + i - 26 * (i ~/ 26)]);
        else id = new String.fromCharCode(65 + i);
      
        return new CellDataGridColumn()
          ..width = 60
          ..minWidth = 20
          ..headerData = new HeaderDataImpl('', null, id, '')
          ..headerItemRendererFactory = new ItemRendererFactory<HeaderItemRenderer<HeaderData>>(constructorMethod: HeaderItemRenderer.construct)
          ..columnItemRendererFactory = new ItemRendererFactory<CellItemRenderer<Cell>>(constructorMethod: CellItemRenderer.construct);
      })
    );
    
    return list;
  }
  
  Row<Cell> _createRow(int rowIndex) {
    final Row<Cell> row = new Row<Cell>(rowIndex);
    
    for (int i=0; i<initCols; i++) row.cells.add(_createCell(toCellIdentity(rowIndex, i), rowIndex, i));
    
    return row;
  }
  
  Cell _createCell(String id, int rowIndex, int colIndex) {
    final Cell cell = new Cell(id, spreadsheet.cells.length, rowIndex, colIndex, null)
      ..onValueChanged.listen((FrameworkEvent event) => lastEditedCell = event.currentTarget as Cell);
    
    spreadsheet.cells.add(cell);
    
    cell.formula.onBodyChanged.listen((FrameworkEvent<String> event) => invalidateFormula(event.currentTarget as Formula));
    
    return cell;
  }
  
  void _updateOverlay([FrameworkEvent event]) {
    _updateRowIndices();
  }
  
  void _updateRowIndices() {
    final int startIndex = spreadsheet.scrollPosition ~/ spreadsheet.rowHeight;
    
    if (spreadsheet.scrollPosition > (spreadsheet.rowHeight * spreadsheet.dataProvider.length - spreadsheet.height) * .95) 
      spreadsheet.dataProvider.addAll(_createRows(spreadsheet.dataProvider.length));
    
    final List<Row<Cell>> columnListDataProvider = new List<Row<Cell>>.generate(columnList.lockIndex, (int i) => spreadsheet.dataProvider[i]);
    
    columnListDataProvider.addAll(spreadsheet.dataProvider.sublist(startIndex + ((columnList.lockIndex >= 0) ? columnList.lockIndex : 0)));
    
    columnList.dataProvider = new ObservableList<Row<Cell>>.from(columnListDataProvider);
  }
  
  void _handleNewRowRenderer(FrameworkEvent<DataGridItemRenderer> event) {
    event.relatedObject.onRendererAdded.listen(_handleNewCellRenderer);
  }
  
  void _handleNewCellRenderer(FrameworkEvent<CellItemRenderer> event) {
    event.relatedObject.onMouseDown.listen(_handleCellDown);
    event.relatedObject.onMouseOver.listen(_handleCellEntry);
    event.relatedObject.onClick.listen(_handleCellClick);
    event.relatedObject.onKey.listen(_handleCellKey);
    event.relatedObject.onSelectionDrag.listen(_continueCurrentSelection);
    
    _updateOverlay();
  }
  
  Cell _selectionStartCell;
  bool _isInSelectionMode = false;
  bool _isInLockedSelectionMode = false;
  
  void _handleCellClick(FrameworkEvent<MouseEvent> event) {
    final CellItemRenderer<Cell> renderer = event.currentTarget as CellItemRenderer;
    
    context.callMethod('__updateCellStream', ['${renderer.data.id}_click', true]);
  }
  
  void _handleCellEntry(FrameworkEvent<MouseEvent> event) {
    if (_isInSelectionMode) {
      final CellItemRenderer<Cell<String>> renderer = event.currentTarget as CellItemRenderer<Cell<String>>;
      
      _cleanCurrentSelection();
      
      _updateCurrentSelection(_selectionStartCell, renderer.data);
    }
  }
  
  void _handleCellDown(FrameworkEvent<MouseEvent> event) {
    selectCell(event.currentTarget as CellItemRenderer<Cell>, isSelectionStart: true);
    
    _operationsManager.start();
  }
  
  void _handleCellKey(FrameworkEvent<KeyboardEvent> event) {
    if (event.relatedObject.keyCode == KeyCode.ENTER) {
      final CellItemRenderer<Cell> cellIR = event.currentTarget as CellItemRenderer<Cell>;
      
      focusCellSibling(cellIR, 1, 0);
      
      event.relatedObject.preventDefault();
      event.relatedObject.stopImmediatePropagation();
    }
  }
  
  void _continueCurrentSelection(FrameworkEvent<Cell> event) {
    StreamSubscription mouseUpSubscription;
    
    _isInSelectionMode = true;
    _isInLockedSelectionMode = true;
    _lockedCells = new List<Cell>.from(_selectedCells);
    
    mouseUpSubscription = document.onMouseUp.listen((MouseEvent event) {
      _isInSelectionMode = false;
      _isInLockedSelectionMode = false;
      
      if (_selectedCells != null && _selectedCells.isNotEmpty) {
        final List<Cell> diffCollection = <Cell>[];
        final Map<int, Cell> originators = <int, Cell>{};
        final bool isHorizontalContinuation = _selectedCells.last.colIndex > _lockedCells.last.colIndex;
          
        _selectedCells.forEach((Cell cell) {
          if (!_lockedCells.contains(cell)) diffCollection.add(cell);
          
          if (isHorizontalContinuation) {
            if (originators[cell.rowIndex] == null || cell.colIndex < originators[cell.rowIndex].colIndex) originators[cell.rowIndex] = cell;
          } else {
            if (originators[cell.colIndex] == null || cell.rowIndex < originators[cell.colIndex].rowIndex) originators[cell.colIndex] = cell;
          }
        });
        
        diffCollection.forEach((Cell cell) {
          final Cell originator = originators[isHorizontalContinuation ? cell.rowIndex : cell.colIndex];
          
          if (originator.formula.body == null) {
            final Iterable matchList = _lockedCells.where((Cell C) {
              if (isHorizontalContinuation) return C.rowIndex == cell.rowIndex;
              else return C.colIndex == cell.colIndex;
            });
            final bool areAllNumbers = matchList.firstWhere((Cell C) => 
                ((C.value != null) ? double.parse(C.value, (_) => double.NAN) : double.NAN).isNaN,
                orElse: () => null
            ) == null;
            
            if (areAllNumbers) {
              final double startValue = ((matchList.first.value != null) ? double.parse(matchList.first.value, (_) => .0) : .0);
              final double step = matchList.fold(
                  startValue, 
                  (dynamic v, Cell C) => ((C.value != null) ? double.parse(C.value, (_) => .0) : .0) - v
              );
              final int lookupRow = isHorizontalContinuation ? cell.rowIndex : cell.rowIndex - 1;
              final int lookupCol = isHorizontalContinuation ? cell.colIndex - 1 : cell.colIndex;
              final dynamic lookupCellValue = getCell(lookupRow, lookupCol).value;
              final double cellValue = ((lookupCellValue != null) ? double.parse(lookupCellValue, (_) => .0) : .0) + step;
            
              cell.value = cellValue.toString();
            } else {
              final int lookupRow = isHorizontalContinuation ? cell.rowIndex : matchList.first.rowIndex + (cell.rowIndex - matchList.first.rowIndex) % matchList.length;
              final int lookupCol = isHorizontalContinuation ? matchList.first.colIndex + (cell.colIndex - matchList.first.colIndex) % matchList.length : cell.colIndex;
                            
              cell.value = getCell(lookupRow, lookupCol).value;
            }
          } else {
            cell.formula.originator = originator;
            cell.formula.body = originator.formula.body;
          }
        });
      }
      
      _lockedCells = null;
      
      mouseUpSubscription.cancel();
    });
  }
  
  void _cleanCurrentSelection() {
    if (_selectedCells != null) _selectedCells.forEach((Cell cell) {
      cell.selected = false;
      cell.selectionOutline = 0;
      cell.isSelectionDragTargetShown = false;
    });
    
    spreadsheet.headerItemRenderers.forEach((IHeaderItemRenderer R) => R.headerData.highlighted = false);
    spreadsheet.dataProvider.forEach((Row<Cell> R) => R.highlighted = false);
  }
  
  void _updateCurrentSelection(Cell minCell, Cell maxCell) {
    IHeaderItemRenderer headerRenderer;
    Row<Cell> row;
    Cell cell;
    int minRowIndex, minColIndex;
    
    _selectedCells = <Cell>[];
    
    if (minCell.globalIndex > maxCell.globalIndex) {
      final Cell tmpCell = minCell;
      
      minCell = maxCell;
      maxCell = tmpCell;
    }
    
    if (_isInLockedSelectionMode) {
      minColIndex = _lockedCells.first.colIndex;
      minRowIndex = _lockedCells.first.rowIndex;
    } else {
      minRowIndex = (minCell.rowIndex < maxCell.rowIndex) ? minCell.rowIndex : maxCell.rowIndex;
      minColIndex = (minCell.colIndex < maxCell.colIndex) ? minCell.colIndex : maxCell.colIndex;
    }
     
    int maxRowIndex = (minCell.rowIndex > maxCell.rowIndex) ? minCell.rowIndex : maxCell.rowIndex;
    int maxColIndex = (minCell.colIndex > maxCell.colIndex) ? minCell.colIndex : maxCell.colIndex;
    
    if (_isInLockedSelectionMode) {
      if (maxColIndex > minColIndex && maxColIndex > _lockedCells.last.colIndex) {
        maxColIndex = max(_lockedCells.last.colIndex, maxColIndex);
        maxRowIndex = _lockedCells.last.rowIndex;
      }
      else if (maxRowIndex > minRowIndex && maxRowIndex > _lockedCells.last.rowIndex) {
        maxColIndex = _lockedCells.last.colIndex;
        maxRowIndex = max(_lockedCells.last.rowIndex, maxRowIndex);
      } else {
        maxColIndex = _lockedCells.last.colIndex;
        maxRowIndex = _lockedCells.last.rowIndex;
      }
    }
    
    final int startIndex = minRowIndex * this.initCols + minColIndex;
    final int endIndex = maxRowIndex * this.initCols + maxColIndex;
    
    for (int i=startIndex; i<=endIndex; i++) {
      cell = spreadsheet.cells[i];
      row = spreadsheet.dataProvider[cell.rowIndex];
      headerRenderer = spreadsheet.headerItemRenderers[cell.colIndex];
      int selectionOutline = 0;
      
      if (
          (cell.rowIndex >= minRowIndex && cell.rowIndex <= maxRowIndex) &&
          (cell.colIndex >= minColIndex && cell.colIndex <= maxColIndex)
      ) {
        cell.selected = true;
        
        row.highlighted = true;
        headerRenderer.headerData.highlighted = true;
        
        _selectedCells.add(cell);
        
        if (cell.rowIndex == minRowIndex) selectionOutline |= 1;
        if (cell.rowIndex == maxRowIndex) selectionOutline |= 4;
        
        if (cell.colIndex == minColIndex) selectionOutline |= 2;
        if (cell.colIndex == maxColIndex) selectionOutline |= 8;
        
        if (_isInLockedSelectionMode) {
          if (cell.rowIndex == _lockedCells.first.rowIndex) selectionOutline |= 1;
          if (cell.rowIndex == _lockedCells.last.rowIndex) selectionOutline |= 4;
          
          if (cell.colIndex == _lockedCells.first.colIndex) selectionOutline |= 2;
          if (cell.colIndex == _lockedCells.last.colIndex) selectionOutline |= 8;
        }
      }
      
      cell.selectionOutline = selectionOutline;
    }
    
    if (_selectedCells.isNotEmpty) _selectedCells.last.isSelectionDragTargetShown = true;
    
    _updateOverlay();
    
    notify('selectedCellsChanged', _selectedCells);
    
    if (_selectedCells.length > 1) notify('selectionStart');
  }
  
  void _hHandleBar_dragHandler(FrameworkEvent<int> event) {
    hHandleBar.y = hHandleBar.paddingTop += event.relatedObject;
  }
  
  void _drag_startHandler(FrameworkEvent event) {
    reflowManager.invalidateCSS(spreadsheet.control, 'pointer-events', 'none');
  }
  
  void _vHandleBar_dragHandler(FrameworkEvent<int> event) {
    vHandleBar.x = vHandleBar.paddingLeft += event.relatedObject;
  }
  
  void _hHandleBar_dragEndHandler(FrameworkEvent event) {
    spreadsheet.rowLockIndex = ((hHandleBar.paddingTop - spreadsheet.headerHeight + hHandleBar.height ~/ 2) / spreadsheet.rowHeight).round();
    
    reflowManager.invalidateCSS(spreadsheet.control, 'pointer-events', 'auto');
    
    invalidateLayout();
  }
  
  void _vHandleBar_dragEndHandler(FrameworkEvent event) {
    int tx = vHandleBar.width ~/ 2 + columnList.x + columnList.width;
    final int dx = vHandleBar.paddingLeft - columnList.x - columnList.width;
    int i = 0;
    
    while (tx < dx) tx += spreadsheet.columns[i++].width;
    
    spreadsheet.columnLockIndex = i;
    
    spreadsheet.reflowManager.invalidateCSS(spreadsheet.control, 'pointer-events', 'auto');
        
    invalidateLayout();
  }
  
  void _registerNewRxSubscription(String cellId, JsObject subscription) => getCellById(cellId).formula.subscriptions.add(subscription);

  JsObject _cellStreamHandler(String selector, {bool forClick: false}) {
    // Select("A:C, 1:10") => A1 to C10 inclusive
    final Selector S = new Selector();
    final List<String> cellIds = S.fromCellSelector(selector, getCell, forClick: forClick);
    Cell cellConflict;
    
    if (_selectedCells != null && _selectedCells.isNotEmpty) {
      cellConflict = _selectedCells.firstWhere((Cell cell) {
        return cellIds.where((String id) => cell.id == id).isNotEmpty;
      }, orElse: () => null);
    }
    
    if (cellConflict != null) {
      cellConflict.formula.isValid = false;
      
      return null;
    }
    
    return context.callMethod('__getMergedStream', cellIds);
  }
  
  JsObject _cellClickStreamHandler(String selector) => _cellStreamHandler(selector, forClick: true);
  
  void _rowStreamHandler(String selector) {
    
  }
  
  void _columnStreamHandler(String selector) {
    
  }
}